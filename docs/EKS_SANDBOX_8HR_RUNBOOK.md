# 8-Hour Sandbox Runbook — Create EKS and Deploy the Whole App

This runbook takes you from an empty AWS sandbox to the running OpenTelemetry
Astronomy Shop on a brand-new **Amazon EKS** cluster, within an 8-hour window.

> The sandbox auto-shuts down, so there is **no manual cleanup**. Deleting the
> sandbox destroys the cluster, node group, and VPC automatically.

## Timeline

| Time | Phase |
|------|-------|
| 0:00–0:30 | Install tools and set AWS credentials |
| 0:30–1:00 | Start EKS cluster creation |
| 1:00–1:20 | Wait for the cluster (~15–20 min) |
| 1:20–2:00 | Deploy the application manifests |
| 2:00–4:00 | Wait for Pods and fix issues |
| 4:00–5:00 | Access the shop and test |
| 5:00–7:30 | Explore services, logs, architecture |
| 7:30–8:00 | Buffer before auto-shutdown |

## 1. Tools and Credentials (0:00–0:30)

Confirm the tools are installed:

```bash
aws --version
eksctl version
kubectl version --client
```

Set the sandbox credentials and region:

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
export AWS_REGION=us-east-1

aws sts get-caller-identity
```

Change `us-east-1` if the sandbox is locked to another region.

## 2. Create the EKS Cluster (0:30–1:20)

This single command creates the VPC, subnets, IAM roles, control plane, and a
managed worker node group. It also configures `kubectl` automatically.

```bash
eksctl create cluster \
  --name otel-demo \
  --region us-east-1 \
  --version 1.30 \
  --nodegroup-name workers \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 3 \
  --nodes-max 4 \
  --managed
```

- `t3.medium` = 2 vCPU / 4 GiB each. Only about 3.2–3.5 GiB per node is
  allocatable after the EKS system Pods (VPC CNI, kube-proxy, CoreDNS).
- The application needs about 4.24 GiB of memory limits. Because these manifests
  set limits without requests, Kubernetes schedules using requests = limits, so
  the total will not fit on one or two `t3.medium` nodes.
- Use **3 nodes** (about 10 GiB allocatable). If any Pod stays `Pending`, scale
  to 4 (see below).
- The largest single Pod is 1.5 GiB, which still fits on one `t3.medium`.
- Creation takes about 15–20 minutes.

Verify the nodes:

```bash
kubectl get nodes -o wide
```

Do not continue until all three nodes report `Ready`.

If Pods later stay `Pending` for lack of memory, add a node:

```bash
eksctl scale nodegroup \
  --cluster otel-demo \
  --name workers \
  --region us-east-1 \
  --nodes 4
```

## 3. Deploy the Whole Application (1:20–2:00)

Run from the repository root:

```bash
kubectl create namespace otel-demo
kubectl apply -n otel-demo -f kubernetes/complete-deploy.yaml
kubectl get pods -n otel-demo -w
```

Wait until the roughly 20 Deployments reach `Running`. Press `Ctrl+C` to stop
watching. Pulling all images can take several minutes.

Check the result:

```bash
kubectl get deployments -n otel-demo
kubectl get services -n otel-demo
```

## 4. Access the Shop (4:00–5:00)

Use port forwarding. It avoids extra ALB and IAM setup.

```bash
kubectl port-forward -n otel-demo \
  service/opentelemetry-demo-frontendproxy 8080:8080
```

Keep the terminal open and visit:

```text
http://localhost:8080
```

## 5. Troubleshooting

Pod stuck in `Pending` (usually not enough node capacity):

```bash
kubectl describe pod <pod-name> -n otel-demo
```

`ImagePullBackOff` (registry access or wrong tag):

```bash
kubectl describe pod <pod-name> -n otel-demo
```

`CrashLoopBackOff` (read logs):

```bash
kubectl logs <pod-name> -n otel-demo
kubectl logs <pod-name> -n otel-demo --previous
```

Page does not open (confirm proxy and restart the port-forward):

```bash
kubectl get pods -n otel-demo \
  --selector opentelemetry.io/name=opentelemetry-demo-frontendproxy
```

## 6. Notes for This Sandbox Run

- No manual cleanup: auto-shutdown removes the cluster, nodes, and VPC.
- Use `t3.medium` x3 (scale to 4 if needed); one or two `t3.medium` nodes will
  not fit the whole application.
- Skip the ALB Ingress; port forwarding is faster for a short session.
- Full observability (Jaeger, Grafana) will not work here. The Kubernetes
  manifests omit the OpenTelemetry Collector, so telemetry connection errors to
  `opentelemetry-demo-otelcol` are expected and safe to ignore.

## 7. Optional Manual Cleanup

Only needed if the sandbox does not auto-delete resources:

```bash
eksctl delete cluster --name otel-demo --region us-east-1
```

This removes the cluster, node group, and the VPC that `eksctl` created.
