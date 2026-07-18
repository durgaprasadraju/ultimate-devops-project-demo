locals {
  argocd_namespace = "argocd"
}

# Install Argo CD itself (server, repo-server, controller, and the CRDs).
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "~> 7.6"
  namespace        = local.argocd_namespace
  create_namespace = true

  # Wait until the CRDs and controllers are ready before the app-of-apps
  # release tries to create Application resources.
  wait    = true
  timeout = 600

  depends_on = [module.eks]
}

# Bootstrap the application: a single Argo CD Application that syncs the
# per-service manifests under kubernetes/ (CI updates those files).
# complete-deploy.yaml is excluded so resources are not applied twice.
resource "helm_release" "argocd_apps" {
  name       = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "~> 2.0"
  namespace  = local.argocd_namespace

  values = [
    yamlencode({
      applications = {
        otel-demo = {
          namespace  = local.argocd_namespace
          project    = "default"
          finalizers = ["resources-finalizer.argocd.argoproj.io"]

          source = {
            repoURL        = var.git_repo_url
            targetRevision = var.git_target_revision
            path           = var.git_manifest_path

            # Per-service folders (productcatalog/, cart/, …) are the GitOps
            # source of truth. CI updates image tags there; Argo CD syncs them.
            # Exclude the monolithic complete-deploy.yaml to avoid duplicates.
            directory = {
              recurse = true
              exclude = "complete-deploy.yaml"
            }
          }

          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = var.app_namespace
          }

          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
            syncOptions = [
              "CreateNamespace=true",
            ]
          }
        }
      }
    })
  ]

  depends_on = [helm_release.argocd]
}
