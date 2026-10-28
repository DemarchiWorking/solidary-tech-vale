# Documentação

Comece por [01-contexto-e-decisoes.md](01-contexto-e-decisoes.md): de onde
o projeto vem, o que mudou do Azure para o GCP e o que foi validado.

## Arquitetura

- [visao-geral.md](arquitetura/visao-geral.md): componentes, caminho de uma doação.
- [rede-e-seguranca.md](arquitetura/rede-e-seguranca.md): VPC, cluster privado, identidade, segredos, cadeia de entrega.
- [dados-e-mensageria.md](arquitetura/dados-e-mensageria.md): Cloud SQL, Pub/Sub e DLQ, Firestore, bucket de DR.
- [exposicao-e-tls.md](arquitetura/exposicao-e-tls.md): Gateway, rotas, certificado.
- Decisões (ADRs):
  [0001](arquitetura/adr/0001-gcp-gke-regional-sao-paulo.md) GKE regional em São Paulo,
  [0002](arquitetura/adr/0002-monorepo-e-nova-arvore.md) monorepo e nova árvore,
  [0003](arquitetura/adr/0003-adaptadores-por-cloud-provider.md) adaptadores por `CLOUD_PROVIDER`,
  [0004](arquitetura/adr/0004-pubsub-dlq-e-idempotencia.md) Pub/Sub, DLQ e idempotência,
  [0005](arquitetura/adr/0005-firestore-no-lugar-do-cosmos-table.md) Firestore,
  [0006](arquitetura/adr/0006-gateway-api-certificate-manager-sslip.md) Gateway API e certificado,
  [0007](arquitetura/adr/0007-identidade-sem-chave.md) identidade sem chave,
  [0008](arquitetura/adr/0008-terraform-em-tres-stacks.md) Terraform em stacks,
  [0009](arquitetura/adr/0009-dr-pilot-light.md) DR pilot light.

## Migração

- [inventario-azure-gcp.md](migracao/inventario-azure-gcp.md): cada arquivo da `main` com Azure e o que virou.
- [nova-arvore.md](migracao/nova-arvore.md): destino de cada um dos arquivos da `main`.
- [criterios-de-aceite.md](migracao/criterios-de-aceite.md): o que foi validado, como, e o que falta na nuvem.

## Plataforma

- [terraform.md](plataforma/terraform.md): estrutura, ordem de apply, state, testes.
- [gitops-argocd.md](plataforma/gitops-argocd.md): app-of-apps, apps, addons, caminho de uma imagem.
- [ci-cd.md](plataforma/ci-cd.md): workflows, variáveis e secrets, self-heal.
- [docker-e-ambiente-local.md](plataforma/docker-e-ambiente-local.md): imagens, compose com emuladores, smoke.
- [observabilidade.md](plataforma/observabilidade.md): coleta, painéis, configuração.

## Operação

- [sre-slo.md](operacao/sre-slo.md): SLIs, SLOs, error budget, resposta automática.
- [finops.md](operacao/finops.md): labels, alavancas de custo, riscos de cota.
- [itsm-aiops.md](operacao/itsm-aiops.md): PagerDuty, ChatOps, Watchdog, fluxo de incidente.
- [pcn-dr.md](operacao/pcn-dr.md): proteção por componente, RPO e RTO, limites.
- Runbooks:
  [01](operacao/runbooks/01-bootstrap-projeto-gcp.md) bootstrap do projeto,
  [02](operacao/runbooks/02-primeiro-deploy.md) primeiro deploy,
  [03](operacao/runbooks/03-rollback.md) rollback,
  [04](operacao/runbooks/04-restore-velero.md) restore (Velero, Cloud SQL, Firestore),
  [05](operacao/runbooks/05-failover-regiao-dr.md) failover de região.
