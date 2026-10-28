# Critérios de aceite da versão GCP

Cada fase da migração só avançou quando o seu critério passou. Tudo o que
está como "passou" roda de novo com `bash scripts/validar.sh` (ou a etapa
indicada), sem nuvem, com as mesmas versões do CI.

## Validado localmente

| Fase | Critério | Como se prova | Resultado |
|---|---|---|---|
| Árvore | caminhos dos workflows, do ArgoCD e do ApplicationSet batem com a árvore nova | `validar.sh workflows` e `gitops` (paths existem, segmento 3, repoURL) | passou |
| Serviços | Go: `go vet`, `go test -race`, golangci-lint v2.15; Python: flake8 e pytest (ngo 4, volunteer 9, notification 15 testes) | `validar.sh servicos` | passou |
| Serviços | backend escolhido por `CLOUD_PROVIDER`, `gcp` padrão, valor inválido falha | `main_test.go`, `test_app.py` de volunteer e notification | passou |
| Imagens | build dos 4 serviços, Trivy no código e na imagem sem CRITICAL, usuário 10001 | `validar.sh imagens` | passou |
| Ambiente local | doação passa por Pub/Sub e chega ao Firestore, voluntário grava e lista, mensagem inválida chega à DLQ, com os containers sem capability e sem escalada de privilégio | `validar.sh e2e` (compose com os emuladores oficiais) | passou |
| Terraform | `fmt`, `validate` nas 6 raízes, 22 testes com `mock_provider`, tflint, Trivy config sem HIGH/CRITICAL | `validar.sh terraform` | passou |
| Terraform | lock dos providers vale no Linux do runner | `terraform init -lockfile=readonly` em `hashicorp/terraform:1.16.2` nas 13 raízes e módulos | passou |
| GitOps | kustomize dos apps e addons, `helm template` dos 6 charts com os values do repositório, `kubeconform -strict` com os schemas das CRDs | `validar.sh gitops` | passou |
| GitOps | KSA, `securityContext`, PDB, VPA, preStop, HTTPRoute no listener `https`, HealthCheckPolicy, hooks `PreSync`, retry, nenhum Ingress, nenhum resto Azure | `scripts/ci/checar_gitops.py` | passou |
| GitOps | SQL do `db-init` roda duas vezes sem erro (hook a cada sync) | PostgreSQL 15 no `gitops-check.sh` | passou |
| GitOps | `configurar-ambiente.sh` preenche tudo e é idempotente | duas execuções com um `terraform` falso | passou |
| CI/CD | 11 workflows sem erro, actions por SHA, `id-token: write` onde há federação, nenhum payload externo interpolado | actionlint 1.7.12 e `checar_workflows.py` (com teste negativo) | passou |
| CI/CD | quatro `update-gitops` simultâneos não perdem atualização | simulação com 4 pushes contra um remoto local, três rodadas | passou (a primeira versão, com 3 tentativas, perdia uma) |
| Docs | links e âncoras resolvem; caminhos citados existem; inventário cobre os 46 arquivos com Azure da `main`; a árvore nova cobre os 108 | `validar.sh docs` e as tabelas geradas a partir do Git | passou |

## Validado na nuvem: pendente

Estes pontos só se provam numa conta GCP com faturamento. O roteiro para
cada um está nos runbooks 01 e 02; marque aqui quando passar.

| Ponto | Como conferir | Status |
|---|---|---|
| Federação do GitHub com o GCP (OIDC para as 4 SAs) | primeiro CI publicando na `main`; job `plan` num PR | pendente |
| Endpoint DNS do GKE com IAM (CI e `kubectl`) | self-heal manual (Run workflow); `kubectl` do runbook 02 | pendente |
| Workload Identity dos pods | doação chegando ao Firestore no cluster | pendente |
| Gateway programado e certificado `ACTIVE` | passo 5 do runbook 02 | pendente |
| As 5 rotas e o redirect HTTP para HTTPS | passo 6 do runbook 02 | pendente |
| DLQ do Pub/Sub real com 10 tentativas e o papel do agente de serviço | publicar uma mensagem inválida no tópico e ler a assinatura `donation-events-dlq-inspecao` | pendente |
| Export diário do Firestore | objeto novo em `gs://<bucket-de-dr>/firestore` no dia seguinte | pendente |
| Velero com Workload Identity | `kubectl -n velero get backups.velero.io` depois das 02:00 | pendente |
| Monitores, SLOs, PagerDuty e self-heal disparando | forçar 5xx num serviço de teste | pendente |
| Restore do Velero e PITR do Cloud SQL | runbook 04 | pendente |
| Failover para `southamerica-west1` | runbook 05, em ensaio | pendente |
