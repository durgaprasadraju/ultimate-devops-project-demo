# Kubernetes LoadBalancer Services create Classic/NLB ELBs (and k8s-elb-*
# security groups) that are NOT in Terraform state. Those ENIs live in public
# subnets, so VPC teardown can hang or fail with DependencyViolation.
#
# Destroy order (depends_on):
#   1. helm / EKS / node groups   (module.eks depends_on this resource)
#   2. this null_resource         — actively delete leftover ELBs + k8s-elb SGs
#   3. module.vpc
resource "null_resource" "wait_for_elb_cleanup" {
  triggers = {
    vpc_id = module.vpc.vpc_id
    region = var.region
  }

  depends_on = [module.vpc]

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      VPC_ID='${self.triggers.vpc_id}'
      REGION='${self.triggers.region}'

      echo "==> Force-deleting load balancers in VPC $VPC_ID"

      for name in $(aws elb describe-load-balancers --region "$REGION" \
        --query "LoadBalancerDescriptions[?VPCId=='$VPC_ID'].LoadBalancerName" \
        --output text 2>/dev/null || true); do
        [[ -z "$name" || "$name" == "None" ]] && continue
        echo "  delete classic ELB: $name"
        aws elb delete-load-balancer --region "$REGION" --load-balancer-name "$name" || true
      done

      for arn in $(aws elbv2 describe-load-balancers --region "$REGION" \
        --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
        --output text 2>/dev/null || true); do
        [[ -z "$arn" || "$arn" == "None" ]] && continue
        echo "  delete elbv2: $arn"
        aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn "$arn" || true
      done

      echo "==> Waiting for ELB ENIs to release"
      for i in $(seq 1 60); do
        CLB=$(aws elb describe-load-balancers --region "$REGION" \
          --query "length(LoadBalancerDescriptions[?VPCId=='$VPC_ID'])" \
          --output text 2>/dev/null || echo 0)
        NLB=$(aws elbv2 describe-load-balancers --region "$REGION" \
          --query "length(LoadBalancers[?VpcId=='$VPC_ID'])" \
          --output text 2>/dev/null || echo 0)
        ENI=$(aws ec2 describe-network-interfaces --region "$REGION" \
          --filters "Name=vpc-id,Values=$VPC_ID" "Name=description,Values=ELB *" \
          --query 'length(NetworkInterfaces)' --output text 2>/dev/null || echo 0)
        CLB=$${CLB//[[:space:]]/}; CLB=$${CLB:-0}; [[ "$CLB" == "None" ]] && CLB=0
        NLB=$${NLB//[[:space:]]/}; NLB=$${NLB:-0}; [[ "$NLB" == "None" ]] && NLB=0
        ENI=$${ENI//[[:space:]]/}; ENI=$${ENI:-0}; [[ "$ENI" == "None" ]] && ENI=0
        if [[ "$CLB" == "0" && "$NLB" == "0" && "$ENI" == "0" ]]; then
          echo "  ELBs and ELB ENIs cleared."
          break
        fi
        echo "  attempt $i/60: classic=$CLB nlb/alb=$NLB elb-enis=$ENI"
        sleep 10
      done

      echo "==> Deleting leftover k8s-elb security groups"
      while read -r sg name; do
        [[ -z "$${sg:-}" || "$sg" == "None" ]] && continue
        if [[ "$name" == k8s-elb-* ]]; then
          echo "  delete SG: $sg ($name)"
          # Clear ingress/egress refs that block SG delete
          aws ec2 revoke-security-group-ingress --region "$REGION" --group-id "$sg" \
            --ip-permissions "$(aws ec2 describe-security-groups --region "$REGION" --group-ids "$sg" \
              --query 'SecurityGroups[0].IpPermissions' --output json)" 2>/dev/null || true
          aws ec2 revoke-security-group-egress --region "$REGION" --group-id "$sg" \
            --ip-permissions "$(aws ec2 describe-security-groups --region "$REGION" --group-ids "$sg" \
              --query 'SecurityGroups[0].IpPermissionsEgress' --output json)" 2>/dev/null || true
          aws ec2 delete-security-group --region "$REGION" --group-id "$sg" || true
        fi
      done < <(aws ec2 describe-security-groups --region "$REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "SecurityGroups[?GroupName!='default'].[GroupId,GroupName]" \
        --output text 2>/dev/null || true)

      echo "==> VPC ELB cleanup finished"
    EOT
  }
}
