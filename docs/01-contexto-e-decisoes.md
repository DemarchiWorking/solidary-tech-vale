# Contexto e decisões

## De onde o projeto vem

A SolidaryTech conecta ONGs, doadores e voluntários. A versão que está na
`main` (e na `branch-azure`) roda no Azure: AKS, ACR, PostgreSQL gerenciado,
Service Bus e Cosmos DB, com Terraform, ArgoCD, Datadog e PagerDuty. Ela
juntou seis repositórios num monorepo, `DemarchiWorking/solidary-tech-vale`,
sem mudar o desenho.

A `branch-gcp` é a mesma plataforma no Google Cloud, pronta para produção:
os mesmos quatro serviços e os mesmos compromissos de SRE, FinOps, ITSM e
continuidade, com os serviços gerenciados do GCP e identidade sem chave.

## O que mudou, em uma tabela

| Tema | Azure (`main`) | GCP (`branch-gcp`) | Por quê |
|---|---|---|---|
| Árvore | `fiap-tc-5-*` na raiz | `services/`, `infra/terraform/`, `deploy/gitops/` | [ADR 0002](arquitetura/adr/0002-monorepo-e-nova-arvore.md) |
| Cluster | AKS | GKE Standard regional em São Paulo, nós privados | [ADR 0001](arquitetura/adr/0001-gcp-gke-regional-sao-paulo.md) |
| Código | Azure com restos de AWS | `CLOUD_PROVIDER=gcp` por padrão, Azure mantido, AWS removido | [ADR 0003](arquitetura/adr/0003-adaptadores-por-cloud-provider.md) |
| Mensageria | Service Bus, `complete` incondicional | Pub/Sub, ack depois de gravar, DLQ e idempotência | [ADR 0004](arquitetura/adr/0004-pubsub-dlq-e-idempotencia.md) |
| NoSQL | Cosmos DB Table | Firestore | [ADR 0005](arquitetura/adr/0005-firestore-no-lugar-do-cosmos-table.md) |
| Entrada | ingress-nginx | Gateway API, Certificate Manager, sslip.io | [ADR 0006](arquitetura/adr/0006-gateway-api-certificate-manager-sslip.md) |
| Identidade | segredos de service principal e do ACR | Workload Identity e Workload Identity Federation | [ADR 0007](arquitetura/adr/0007-identidade-sem-chave.md) |
| IaC | uma raiz | stacks infra, platform e observability por ambiente | [ADR 0008](arquitetura/adr/0008-terraform-em-tres-stacks.md) |
| DR | backups | pilot light em `southamerica-west1` | [ADR 0009](arquitetura/adr/0009-dr-pilot-light.md) |

## Escolhas feitas no planejamento

Antes de implementar, quatro pontos foram decididos junto com o dono do
projeto: reorganizar a árvore; GKE Standard regional em
`southamerica-east1`; HTTPS com `<ip>.sslip.io` e certificado do Google, sem
domínio próprio; e manter os adaptadores Azure no código, com `gcp` como
padrão. Também ficou decidido que esta entrega é validada localmente e fica
pronta para a nuvem por runbook, porque a subida real exige um projeto com
faturamento.

## O que "validado" quer dizer aqui

Tudo o que dá para provar sem nuvem foi provado e roda num comando
(`bash scripts/validar.sh`):

- os serviços rodam contra Pub/Sub e Firestore reais, nos emuladores
  oficiais, num teste que passa por todo o caminho da doação e pela DLQ;
- o Terraform passa em `validate`, em 22 testes com `mock_provider`, no
  tflint e no Trivy;
- os manifests passam no `kubeconform` estrito com os schemas das CRDs;
- os workflows passam no actionlint e nas checagens estruturais, e os
  comandos de cada job rodaram localmente.

O que só se prova numa conta GCP (Gateway e certificado, Workload Identity
em execução, federação com o GitHub, DLQ do Pub/Sub real, endpoint DNS do
GKE, export do Firestore, failover) está marcado nos documentos como
"validado na nuvem: pendente" e listado em
[migracao/criterios-de-aceite.md](migracao/criterios-de-aceite.md).
