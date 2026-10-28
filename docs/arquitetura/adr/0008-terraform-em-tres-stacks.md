# ADR 0008. Terraform em stacks separadas por ambiente

Status: aceita (branch-gcp)

## Contexto

Os providers `kubernetes` e `helm` precisam de um cluster que já exista para
serem configurados. Numa raiz única, o primeiro `plan` falha ou depende de
truques de ordem; um `destroy` também fica frágil.

## Decisão

Três raízes em produção, cada uma com o seu state no GCS, ligadas por
`terraform_remote_state` (prefixos em `versions.tf`):

| Raiz | Providers | Cria |
|---|---|---|
| `envs/prod/infra` | google | rede, GKE, Cloud SQL, Pub/Sub, Firestore, Artifact Registry, IP e certificado, Workload Identity |
| `envs/prod/platform` | kubernetes, helm | namespaces, Secrets, ConfigMap `gcp-config`, ArgoCD e o app-of-apps, RBAC do self-heal |
| `envs/prod/observability` | datadog, pagerduty | monitores, SLOs, Watchdog, PagerDuty e webhooks |

O DR tem duas (`envs/dr/infra` e `envs/dr/platform`). O `bootstrap` é uma
raiz à parte, aplicada uma vez com credencial de usuário.

Os providers `kubernetes` e `helm` falam com o endpoint DNS do GKE
(`https://<dns_endpoint>`) com o token do `google_client_config`, sem CA.

## Consequências

- Ordem de apply fixa: bootstrap, infra, platform, observability (o
  workflow `terraform.yaml` segue a mesma ordem).
- A stack de observabilidade não depende do GCP e pode ser aplicada antes
  do cluster.
- Cada módulo tem `terraform test` com `mock_provider`, que roda sem nuvem no
  CI e no `scripts/validar.sh` (`scripts/ci/terraform-check.sh`).
