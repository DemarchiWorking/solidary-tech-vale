# SolidaryTech no Google Cloud

Plataforma que conecta ONGs, doadores e voluntários, com quatro
microsserviços em GKE, entrega por GitOps e CI/CD no GitHub Actions. Esta é
a `branch-gcp`; a versão Azure está na `main` e na `branch-azure`.

| Serviço | Linguagem | Faz | Guarda em |
|---|---|---|---|
| `ngo-service` | Python 3.12 | cadastro e listagem de ONGs (`/ngos`) | Cloud SQL `ngo_db` |
| `donation-service` | Go 1.26 | registro de doações (`/donations`) e evento no Pub/Sub | Cloud SQL `donation_db` |
| `volunteer-service` | Python 3.12 | voluntários por ONG (`/volunteers`) | Firestore `volunteers` |
| `notification-service` | Python 3.12 | consome as doações e registra a notificação | Firestore `donation_notifications` |

```
Internet ──HTTPS──► Gateway (LB global, Certificate Manager, <ip>.sslip.io)
                        │
         ┌──────────────┼───────────────┐
     ngo-service  donation-service  volunteer-service
         │              │                │
     Cloud SQL ◄────────┤            Firestore ◄── notification-service
                        └──► Pub/Sub ─────────────────┘   (DLQ após 10 tentativas)

GKE Standard regional (southamerica-east1), nós privados, Workload Identity
DR pilot light em southamerica-west1
```

## Estrutura

```
services/          os 4 microsserviços (código, testes, Dockerfile)
infra/terraform/   bootstrap, módulos e ambientes (prod, dr)
deploy/gitops/     o que o ArgoCD aplica: apps, addons, applicationsets
scripts/           ambiente local, smoke e os gates do CI
docs/              arquitetura, migração, plataforma e operação
.github/workflows/ CI dos serviços, self-heal, Terraform, GitOps, E2E
```

O mapa de cada arquivo da versão Azure para esta árvore está em
[docs/migracao/nova-arvore.md](docs/migracao/nova-arvore.md).

## Rodar localmente

Precisa de Docker. Sobe Postgres, os emuladores oficiais do Pub/Sub e do
Firestore, o OTel Collector e os 4 serviços com `CLOUD_PROVIDER=gcp`:

```bash
docker compose up -d --build --wait
```

```bash
bash scripts/smoke-local.sh
```

```bash
docker compose down -v
```

Os serviços respondem em `http://127.0.0.1:9081` a `9084`. Detalhes em
[docs/plataforma/docker-e-ambiente-local.md](docs/plataforma/docker-e-ambiente-local.md).

## Validar tudo

```bash
bash scripts/validar.sh
```

Roda, sem nuvem e com as mesmas versões do CI: testes e lint dos serviços,
build e Trivy das imagens, o gate do Terraform (`validate`, `terraform test`,
tflint, Trivy), o gate do GitOps (kustomize, helm template, kubeconform,
checagens), actionlint e checagens dos workflows, a checagem da
documentação e o E2E com `docker compose`. Uma etapa só:
`bash scripts/validar.sh gitops`.

## Subir no GCP

1. [Bootstrap do projeto](docs/operacao/runbooks/01-bootstrap-projeto-gcp.md):
   APIs, state, federação do GitHub e SAs do CI, uma vez.
2. [Primeiro deploy](docs/operacao/runbooks/02-primeiro-deploy.md): merge da
   `branch-gcp` na `main`, Terraform, valores do ambiente no GitOps,
   primeiras imagens, Gateway e certificado.

Depois disso, cada push na `main` testa, publica a imagem no Artifact
Registry, grava a tag no GitOps e o ArgoCD aplica; mudanças em
`infra/terraform` passam por plan no PR e apply com aprovação no
environment `production`. Nenhuma chave de nuvem fica no GitHub.

## Documentação

Índice em [docs/README.md](docs/README.md). Para entender as escolhas,
comece por [docs/01-contexto-e-decisoes.md](docs/01-contexto-e-decisoes.md).
