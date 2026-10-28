# ============================================
# Plataforma no cluster: namespaces, Secrets, ConfigMap, ArgoCD e RBAC
# ============================================
# Roda numa stack separada da infraestrutura (envs/<env>/platform), com os
# providers kubernetes/helm apontando para o endpoint DNS de um cluster que
# já existe. Nenhuma credencial passa pelo Git: o GitOps só referencia os
# nomes dos Secrets criados aqui.

locals {
  namespaces = toset(["ngo", "donation", "volunteer", "notification", "monitoring", "velero", "sonarqube", "gateway"])

  # Serviços que usam Pub/Sub ou Firestore e por isso leem o projeto do
  # ConfigMap gcp-config.
  gcp_apps = toset(["donation", "volunteer", "notification"])

  # Namespaces onde o self-heal (GitHub Actions) pode reiniciar Deployments.
  selfheal_namespaces = toset(["ngo", "donation", "volunteer", "notification"])

  # Namespaces que podem pendurar rotas no listener HTTPS do Gateway
  # (selector solidarytech.io/gateway=true em addons/gateway).
  gateway_namespaces = toset(["ngo", "donation", "volunteer", "monitoring", "sonarqube"])
}

resource "kubernetes_namespace_v1" "this" {
  for_each = local.namespaces

  metadata {
    name   = each.value
    labels = contains(local.gateway_namespaces, each.value) ? { "solidarytech.io/gateway" = "true" } : {}
  }

  # O ArgoCD também usa esses namespaces (CreateNamespace=true) e pode
  # acrescentar labels/annotations: não brigar com ele. A label do Gateway
  # entra na criação.
  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

# --- Configuração não secreta lida pelos Deployments ---
resource "kubernetes_config_map_v1" "gcp_config" {
  for_each = local.gcp_apps

  metadata {
    name      = "gcp-config"
    namespace = kubernetes_namespace_v1.this[each.value].metadata[0].name
  }

  data = {
    GCP_PROJECT_ID = var.project_id
  }
}

# --- Bancos (Cloud SQL, IP privado) ---
resource "kubernetes_secret_v1" "ngo_db" {
  metadata {
    name      = "db-secrets"
    namespace = kubernetes_namespace_v1.this["ngo"].metadata[0].name
  }
  data = {
    ngo-database-url = var.database_urls["ngo"]
  }
}

resource "kubernetes_secret_v1" "donation_db" {
  metadata {
    name      = "db-secrets"
    namespace = kubernetes_namespace_v1.this["donation"].metadata[0].name
  }
  data = {
    donation-database-url = var.database_urls["donation"]
  }
}

# --- Observabilidade ---
resource "kubernetes_secret_v1" "datadog_api_key" {
  metadata {
    name      = "datadog-api-key"
    namespace = kubernetes_namespace_v1.this["monitoring"].metadata[0].name
  }
  data = {
    DD_API_KEY = var.datadog_api_key
  }
}

resource "random_password" "grafana_admin" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.this["monitoring"].metadata[0].name
  }
  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  }
}

# --- SonarQube: banco no Cloud SQL, senha do admin e passcode ---
resource "kubernetes_secret_v1" "sonarqube_jdbc" {
  metadata {
    name      = "sonarqube-jdbc"
    namespace = kubernetes_namespace_v1.this["sonarqube"].metadata[0].name
  }
  data = {
    jdbc-password = var.sonarqube_db_password
  }
}

# O SonarQube exige senha forte (maiúscula, minúscula, número e símbolo).
resource "random_password" "sonarqube_admin" {
  length           = 24
  special          = true
  override_special = "!#%*-_=+"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "kubernetes_secret_v1" "sonarqube_admin" {
  metadata {
    name      = "sonarqube-admin"
    namespace = kubernetes_namespace_v1.this["sonarqube"].metadata[0].name
  }
  # O hook do chart troca a senha padrão (currentPassword) pela nova.
  data = {
    password        = random_password.sonarqube_admin.result
    currentPassword = "admin"
  }
}

resource "random_password" "sonarqube_monitoring" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "sonarqube_monitoring" {
  metadata {
    name      = "sonarqube-monitoring"
    namespace = kubernetes_namespace_v1.this["sonarqube"].metadata[0].name
  }
  data = {
    passcode = random_password.sonarqube_monitoring.result
  }
}

# --- ArgoCD (ClusterIP: acesso por port-forward, sem IP público) ---
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true

  values = [yamlencode({
    server = {
      service = { type = "ClusterIP" }
    }
    configs = {
      params = {
        "kustomize.buildOptions" = "--enable-helm"
      }
      repositories = {
        gitops-repo = {
          url  = var.gitops_repo_url
          type = "git"
        }
      }
    }
  })]

  # Repositório privado: token fine-grained só de leitura (Contents: Read).
  set_sensitive = var.argocd_github_token == "" ? [] : [
    {
      name  = "configs.repositories.gitops-repo.username"
      value = "x-access-token"
    },
    {
      name  = "configs.repositories.gitops-repo.password"
      value = var.argocd_github_token
    },
  ]
}

# --- App-of-apps: o único ponto de entrada do ArgoCD ---
resource "helm_release" "root_app" {
  name      = "argocd-root"
  chart     = "argocd-apps"
  version   = var.argocd_apps_chart_version
  namespace = "argocd"

  repository = "https://argoproj.github.io/argo-helm"

  values = [yamlencode({
    applications = {
      bootstrap = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_revision
          path           = var.gitops_entry_path
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = { prune = true, selfHeal = true }
          retry = {
            limit   = 10
            backoff = { duration = "10s", factor = 2, maxDuration = "5m" }
          }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}

# --- Self-heal: a GSA do GitHub Actions só reinicia Deployments ---
resource "kubernetes_role_v1" "selfheal" {
  for_each = local.selfheal_namespaces

  metadata {
    name      = "selfheal-rollout-restart"
    namespace = kubernetes_namespace_v1.this[each.value].metadata[0].name
  }

  # watch: o `kubectl rollout status` acompanha o Deployment por watch.
  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch", "patch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["replicasets"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_role_binding_v1" "selfheal" {
  for_each = var.selfheal_service_account == "" ? toset([]) : local.selfheal_namespaces

  metadata {
    name      = "selfheal-rollout-restart"
    namespace = kubernetes_namespace_v1.this[each.value].metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.selfheal[each.value].metadata[0].name
  }

  subject {
    kind      = "User"
    name      = var.selfheal_service_account
    api_group = "rbac.authorization.k8s.io"
  }
}
