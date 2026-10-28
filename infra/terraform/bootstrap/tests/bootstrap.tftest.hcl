# Valores no formato real, para os recursos que validam o formato (os
# bindings exigem um nome de SA de verdade).
mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      name  = "projects/solidarytech-test/serviceAccounts/ci-deployer@solidarytech-test.iam.gserviceaccount.com"
      email = "ci-deployer@solidarytech-test.iam.gserviceaccount.com"
    }
  }
  mock_resource "google_iam_workload_identity_pool" {
    defaults = {
      name = "projects/123456789012/locations/global/workloadIdentityPools/github"
    }
  }
  mock_data "google_project" {
    defaults = {
      number = "123456789012"
    }
  }
}
mock_provider "google-beta" {}

variables {
  project_id = "solidarytech-test"
}

run "wif_restrito_ao_repositorio_pelo_nome" {
  command = plan

  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.repository == 'DemarchiWorking/solidary-tech-vale'"
    error_message = "Sem IDs, a federação precisa ficar restrita ao repositório pelo nome."
  }
  assert {
    condition     = length(google_billing_budget.monthly) == 0
    error_message = "Sem conta de faturamento, sem orçamento."
  }
}

run "wif_pelos_ids_imutaveis" {
  command = plan

  variables {
    github_repository_id = "987654321"
    github_owner_id      = "56514877"
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.repository_id == '987654321' && assertion.repository_owner_id == '56514877'"
    error_message = "Com IDs, a condição usa repository_id e repository_owner_id."
  }
}

# apply (com mock): o nome do pool só existe depois de criado.
run "cada_sa_presa_ao_seu_tipo_de_job" {
  command = apply

  assert {
    condition     = endswith(google_service_account_iam_member.terraform_wif.member, "/subject/repo:DemarchiWorking/solidary-tech-vale:environment:production")
    error_message = "O apply só pode vir do environment production."
  }
  assert {
    condition     = endswith(google_service_account_iam_member.plan_wif.member, "/subject/repo:DemarchiWorking/solidary-tech-vale:pull_request")
    error_message = "A SA de plan só pode vir de pull request."
  }
  assert {
    condition     = endswith(google_service_account_iam_member.deployer_wif.member, "/attribute.ref/refs/heads/main")
    error_message = "Publicar imagem só a partir da branch padrão."
  }
  assert {
    condition     = google_project_iam_member.selfheal.role == "roles/container.viewer"
    error_message = "O self-heal só lê o cluster (connect no endpoint DNS); reiniciar é RBAC."
  }
}
