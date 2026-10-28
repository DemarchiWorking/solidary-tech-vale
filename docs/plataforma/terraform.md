# Terraform

Tudo em `infra/terraform`, com Terraform 1.16 e o provider `google` 8.9. As
versões dos providers estão travadas nos `.terraform.lock.hcl` versionados;
um `terraform init -lockfile=readonly` no Linux (o sistema do runner do CI)
passa em todas as raízes e módulos.

## Estrutura

```
infra/terraform/
├── .tflint.hcl                 tflint com o ruleset google 0.41.0
├── bootstrap/                  uma vez, com a sua credencial
├── modules/
│   ├── network/                VPC, sub-redes, Cloud NAT, Private Service Access
│   ├── gke/                    cluster regional e pool de nós
│   ├── data/                   Cloud SQL, Pub/Sub e DLQ, Firestore, bucket de DR
│   ├── workload-identity/      papéis das KSAs e GSA do Velero
│   ├── edge/                   IP global, host sslip.io, certificado e certmap
│   ├── platform/               namespaces, Secrets, ArgoCD, app-of-apps, RBAC
│   └── observability/          Datadog, PagerDuty, ChatOps, self-heal
└── envs/
    ├── prod/infra              usa network, gke, data, edge, workload-identity
    ├── prod/platform           usa platform (lê o state de prod/infra)
    ├── prod/observability      usa observability
    ├── dr/infra                réplica do Cloud SQL e GKE de contingência (desligado)
    └── dr/platform             ArgoCD no cluster de DR
```

O motivo de separar infra, platform e observability está na
[ADR 0008](../arquitetura/adr/0008-terraform-em-tres-stacks.md).

## Ordem de apply

| Passo | Raiz | Precisa de |
|---|---|---|
| 1 | `bootstrap` | projeto com faturamento; `gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com` |
| 2 | `envs/prod/infra` | `project_id`, `ci_deployer_service_account` (output do passo 1) |
| 3 | `envs/prod/platform` | `state_bucket`, `datadog_api_key`, `argocd_github_token` (repositório privado), `selfheal_service_account` |
| 4 | `envs/prod/observability` | chaves do Datadog, token do PagerDuty, webhook do Discord, token do self-heal |
| DR | `envs/dr/infra`, `envs/dr/platform` | só no failover (runbook 05) |

O passo a passo com os comandos está no
[runbook 01](../operacao/runbooks/01-bootstrap-projeto-gcp.md) e no
[runbook 02](../operacao/runbooks/02-primeiro-deploy.md). Depois do
bootstrap, os passos 2 a 4 rodam pelo workflow `terraform.yaml` no
environment `production`.

## State

Um bucket GCS por projeto (`<projeto>-tfstate`, criado pelo bootstrap), com
um prefixo por raiz (`bootstrap`, `prod/infra`, `prod/platform`,
`prod/observability`, `dr/infra`, `dr/platform`). O `backend.hcl` de cada
raiz (gitignorado) só tem o nome do bucket; há um `.example` em cada pasta.

## Labels

Todo recurso que aceita label recebe, pelo `default_labels` do provider
(`envs/prod/infra/versions.tf`): `project=solidarytech`,
`environment=production`, `costcenter=ngo-core`, `managed-by=terraform`, e
`component` quando faz sentido. A relação com as tags da versão Azure está
em [finops.md](../operacao/finops.md).

## Testes e lint (sem nuvem)

`bash scripts/ci/terraform-check.sh` roda, nesta ordem:

1. `terraform fmt -check -recursive`;
2. `terraform validate` nas 6 raízes;
3. `terraform test` nos 7 módulos e no bootstrap, com `mock_provider` (22
   execuções de teste no total), cobrindo, entre outros: cluster regional,
   privado e com Workload Identity; Cloud SQL HA e só com IP privado; DLQ
   com 10 tentativas; labels; condição da federação do GitHub; ArgoCD em
   ClusterIP e app-of-apps com retry; RBAC do self-heal com `watch` e
   `patch`;
4. `tflint --recursive` com o ruleset do Google;
5. Trivy `config`, bloqueando HIGH e CRITICAL.

O `validate` de `envs/prod/infra` e `envs/dr/infra` mostra um aviso de
depreciação do provider sobre `remove_default_node_pool`; o comentário em
`modules/gke/main.tf` explica por que o argumento continua.

O mesmo script roda no job `static` do `.github/workflows/terraform.yaml` e
no `scripts/validar.sh`.
