# ADR 0005. Firestore no lugar do Cosmos DB (API Table)

Status: aceita (branch-gcp)

## Contexto

Voluntários e notificações processadas ficavam no Cosmos DB com a API
Table: chave de partição pela ONG, consultas por ONG e nenhum relacionamento.

## Decisão

Firestore nativo, banco `(default)` em `southamerica-east1`, com PITR,
proteção contra exclusão e backup diário com retenção de 7 dias
(`infra/terraform/modules/data/main.tf`).

| Dado | Coleção | Chave do documento | Consulta |
|---|---|---|---|
| Voluntários | `volunteers` | `volunteer_id` | `where ngo_id == <id>` |
| Notificações | `donation_notifications` | `event_id` | leitura por id |

O acesso é por Workload Identity com `roles/datastore.user` para as KSAs do
volunteer-service e do notification-service
(`infra/terraform/modules/workload-identity/main.tf`). O IAM do Firestore é
por projeto: não existe papel por coleção.

## Consequências

- Sem servidor, sem capacidade provisionada e sem connection string.
- O backup gerenciado do Firestore só restaura na mesma região. Para o DR,
  um job do Cloud Scheduler exporta o banco todo dia para o bucket de DR em
  `southamerica-west1` (ver [ADR 0009](0009-dr-pilot-light.md)).
- O volunteer-service e o notification-service rodam contra o emulador
  oficial no ambiente local (`docker-compose.yml`), e o smoke confere os
  documentos pela API REST do emulador.
