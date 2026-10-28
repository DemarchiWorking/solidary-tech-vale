# tflint para todas as stacks e módulos (roda com --recursive na raiz de
# infra/terraform; o CI usa a mesma configuração).
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "google" {
  enabled = true
  version = "0.41.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}
