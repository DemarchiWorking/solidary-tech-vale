mock_provider "kubernetes" {}
mock_provider "helm" {}
mock_provider "random" {}

variables {
  project_id               = "solidarytech-test"
  database_urls            = { ngo = "postgres://ngo_app:x@10.40.0.5:5432/ngo_db?sslmode=require", donation = "postgres://donation_app:y@10.40.0.5:5432/donation_db?sslmode=require" }
  sonarqube_db_password    = "z"
  datadog_api_key          = "k"
  gitops_repo_url          = "https://github.com/DemarchiWorking/solidary-tech-vale.git"
  selfheal_service_account = "ci-selfheal@solidarytech-test.iam.gserviceaccount.com"
}

run "argocd_privado_e_app_of_apps" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.argocd.values[0]).server.service.type == "ClusterIP"
    error_message = "O ArgoCD não pode ter IP público."
  }
  assert {
    condition     = yamldecode(helm_release.root_app.values[0]).applications.bootstrap.source.path == "deploy/gitops/applicationsets"
    error_message = "O app-of-apps aponta para deploy/gitops/applicationsets."
  }
  assert {
    condition     = yamldecode(helm_release.root_app.values[0]).applications.bootstrap.syncPolicy.retry.limit == 10
    error_message = "O app-of-apps precisa de retry (primeiro sync antes das CRDs)."
  }
}

run "secrets_e_configmap_com_os_nomes_do_gitops" {
  command = plan

  assert {
    condition     = kubernetes_secret_v1.ngo_db.metadata[0].name == "db-secrets" && kubernetes_secret_v1.donation_db.metadata[0].name == "db-secrets"
    error_message = "Os Deployments leem o Secret db-secrets."
  }
  assert {
    condition     = length(kubernetes_config_map_v1.gcp_config) == 3
    error_message = "gcp-config em donation, volunteer e notification."
  }
  assert {
    condition     = contains(keys(kubernetes_secret_v1.sonarqube_admin.data), "currentPassword")
    error_message = "O hook do SonarQube espera password e currentPassword."
  }
}

run "namespaces_liberados_no_gateway" {
  command = plan

  assert {
    condition     = kubernetes_namespace_v1.this["donation"].metadata[0].labels["solidarytech.io/gateway"] == "true" && kubernetes_namespace_v1.this["sonarqube"].metadata[0].labels["solidarytech.io/gateway"] == "true"
    error_message = "Namespaces com rota precisam da label do Gateway."
  }
  assert {
    condition     = length(kubernetes_namespace_v1.this["velero"].metadata[0].labels) == 0
    error_message = "Namespaces sem rota não entram no Gateway."
  }
}

run "rbac_do_selfheal_por_namespace" {
  command = plan

  assert {
    condition     = length(kubernetes_role_binding_v1.selfheal) == 4
    error_message = "Um RoleBinding por namespace de serviço."
  }
  assert {
    condition     = contains(kubernetes_role_v1.selfheal["donation"].rule[0].verbs, "watch") && contains(kubernetes_role_v1.selfheal["donation"].rule[0].verbs, "patch")
    error_message = "rollout restart (patch) e rollout status (watch) nos Deployments."
  }
}

run "sem_sa_de_selfheal_sem_binding" {
  command = plan

  variables {
    selfheal_service_account = ""
  }

  assert {
    condition     = length(kubernetes_role_binding_v1.selfheal) == 0
    error_message = "Sem SA de self-heal, nenhum RoleBinding."
  }
}
