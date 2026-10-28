# Runbook 01. Bootstrap do projeto GCP

Uma vez por projeto. Deixa pronto o que o CI precisa para trabalhar sozinho:
APIs, bucket do state do Terraform, federação de identidade do GitHub e as
service accounts do CI.

## Antes

- Projeto GCP com faturamento ativo e você como Owner.
- `gcloud`, Terraform 1.16 e, opcional, `gh` logado.
- Cota de vCPU em `southamerica-east1` de pelo menos 12 para o teto do
  cluster (IAM e administrador > Cotas); com menos, reduza
  `max_nodes_per_zone` no runbook 02.

## Passos

1. Login e APIs mínimas (o Terraform habilita o resto):

   ```bash
   gcloud auth login
   ```

   ```bash
   gcloud auth application-default login
   ```

   ```bash
   gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com --project <id-do-projeto>
   ```

2. Variáveis do bootstrap:

   ```bash
   cd infra/terraform/bootstrap && cp terraform.tfvars.example terraform.tfvars
   ```

   Preencha `project_id`. Recomendado: os IDs numéricos do repositório e do
   dono, que impedem um repositório recriado com o mesmo nome de herdar o
   acesso:

   ```bash
   gh api repos/DemarchiWorking/solidary-tech-vale --jq .id
   ```

   ```bash
   gh api users/DemarchiWorking --jq .id
   ```

   Opcional: `billing_account` (de `gcloud billing accounts list`) para o
   orçamento mensal com alertas.

3. Primeiro apply, com state local:

   ```bash
   terraform init && terraform apply
   ```

4. Levar o state para o bucket que acabou de ser criado:

   ```bash
   cp backend.tf.example backend.tf
   ```

   ```bash
   terraform init -migrate-state -backend-config="bucket=$(terraform output -raw state_bucket)"
   ```

5. Cadastrar no GitHub (Settings > Secrets and variables > Actions >
   Variables) os outputs:

   | Variável | Output |
   |---|---|
   | `GCP_PROJECT_ID` | o ID do projeto |
   | `GCP_WIF_PROVIDER` | `workload_identity_provider` |
   | `GCP_CI_SA` | `ci_deployer_service_account` |
   | `GCP_SELFHEAL_SA` | `ci_selfheal_service_account` |
   | `GCP_TF_PLAN_SA` | `ci_terraform_plan_service_account` |
   | `GCP_TF_APPLY_SA` | `ci_terraform_service_account` |
   | `TF_STATE_BUCKET` | `state_bucket` |

   ```bash
   terraform output
   ```

6. Criar o environment `production` (Settings > Environments), de
   preferência com revisor obrigatório, e cadastrar nele os secrets do
   apply: `DD_API_KEY`, `ARGOCD_GITHUB_TOKEN` (se o repositório for
   privado; token fine-grained com Contents: Read) e, para a observabilidade,
   `DD_APP_KEY`, `PAGERDUTY_TOKEN`, `DISCORD_WEBHOOK_URL` e
   `GH_SELFHEAL_TOKEN` (token fine-grained deste repositório com Contents:
   Read and write), mais a variável `PAGERDUTY_USER_EMAIL`.

## Conferir

```bash
gcloud iam workload-identity-pools providers list --location=global --workload-identity-pool=github --project <id-do-projeto>
```

O provider aparece com a condição do repositório. A federação de fato só é
exercitada no primeiro workflow que chamar o GCP (runbook 02).

## Se der errado

- `Permission denied` ao habilitar APIs: a conta precisa de Owner ou
  `serviceusage.serviceUsageAdmin`.
- Erro do Pub/Sub sobre o agente de serviço: rode o apply de novo; o agente
  é criado pela primeira chamada à API e pode demorar alguns segundos.
