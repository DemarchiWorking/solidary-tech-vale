# Vão para as variáveis do GitHub (Settings > Secrets and variables >
# Actions > Variables) e para os terraform.tfvars das outras stacks.

output "state_bucket" {
  value = google_storage_bucket.tfstate.name
}

output "workload_identity_provider" {
  description = "Variável GCP_WIF_PROVIDER do GitHub"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "ci_deployer_service_account" {
  description = "Variável GCP_CI_SA do GitHub e ci_deployer_service_account de envs/prod/infra"
  value       = google_service_account.ci["ci-deployer"].email
}

output "ci_selfheal_service_account" {
  description = "Variável GCP_SELFHEAL_SA do GitHub e selfheal_service_account de envs/prod/platform"
  value       = google_service_account.ci["ci-selfheal"].email
}

output "ci_terraform_plan_service_account" {
  description = "Variável GCP_TF_PLAN_SA do GitHub"
  value       = google_service_account.ci["ci-terraform-plan"].email
}

output "ci_terraform_service_account" {
  description = "Variável GCP_TF_APPLY_SA do GitHub"
  value       = google_service_account.ci["ci-terraform"].email
}

output "pubsub_service_agent" {
  value = google_project_service_identity.pubsub.member
}
