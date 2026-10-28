# Dados e mensageria

Tudo nesta página vem de `infra/terraform/modules/data/main.tf` e das
variáveis em `modules/data/variables.tf`, salvo indicação.

## Cloud SQL (PostgreSQL 15)

| Item | Valor |
|---|---|
| Edição e disponibilidade | ENTERPRISE, `REGIONAL` (primária e standby em zonas diferentes, failover automático) |
| Máquina | `db-custom-1-3840` (1 vCPU, 3,75 GB), disco PD_SSD |
| Rede | só IP privado pela VPC (Private Service Access), `ENCRYPTED_ONLY` |
| Backup | diário, 14 backups guardados em `southamerica-west1` |
| PITR | 7 dias de log de transações |
| Bancos | `ngo_db`, `donation_db`, `sonarqube` |
| Usuários | `ngo_app`, `donation_app`, `sonarqube`, com senha gerada pelo Terraform |
| Outros | janela de manutenção definida, Query Insights ligado, nome com sufixo aleatório (o Cloud SQL não deixa reusar o nome de uma instância excluída por cerca de uma semana) |

As tabelas são criadas pelos Jobs `db-init` de cada app, que rodam como hook
`PreSync` do ArgoCD com o `db/init.sql` do serviço
(`deploy/gitops/apps/{ngo,donation}/overlays/prod/db-init-job.yaml`). O
ConfigMap com o SQL entra na onda `-1`, antes do Job.

Os usuários criados pela API do Cloud SQL pertencem ao `cloudsqlsuperuser`.
Para que o `ngo_app` não consiga abrir o `donation_db` (e vice-versa), o
passo seguinte, a ser feito no banco depois do primeiro deploy, é:

```sql
REVOKE CONNECT ON DATABASE donation_db FROM PUBLIC;
GRANT  CONNECT ON DATABASE donation_db TO donation_app;
REVOKE CONNECT ON DATABASE ngo_db FROM PUBLIC;
GRANT  CONNECT ON DATABASE ngo_db TO ngo_app;
```

## Pub/Sub

```
donation-service ──publish──► donation-events ──► notification-service (assinatura)
                                                     │ depois de 10 entregas
                                                     ▼
                                              donation-events-dlq ──► donation-events-dlq-inspecao
```

| Recurso | Configuração |
|---|---|
| Tópico `donation-events` | retenção de 7 dias |
| Assinatura `notification-service` | ack deadline 60 s, retry de 10 s a 600 s, DLQ com 10 tentativas |
| Tópico `donation-events-dlq` | retenção de 7 dias |
| Assinatura `donation-events-dlq-inspecao` | para ler e reprocessar o que caiu na DLQ |
| Alerta | Cloud Monitoring avisa quando há mensagem não entregue na DLQ |

O agente de serviço do Pub/Sub (`service-<número>@gcp-sa-pubsub`) recebe
publisher na DLQ e subscriber na assinatura de origem; sem isso a mensagem
não é movida. O `bootstrap` cria esse agente antes
(`google_project_service_identity`), porque ele só existe depois da primeira
chamada à API.

Contrato da mensagem (`services/donation-service/queue.go`): corpo JSON da
doação (`id`, `ngo_id`, `amount`, `donor_name`, `created_at`) e os atributos
`event_id` (UUID) e `traceparent`/`tracestate`.

Regra do consumidor (`services/notification-service/app.py`): grava e só
então dá ack; erro de gravação ou JSON inválido vira nack. O documento é
`donation_notifications/<event_id>`, então uma entrega repetida reescreve o
mesmo documento. Detalhes e motivo na
[ADR 0004](adr/0004-pubsub-dlq-e-idempotencia.md).

## Firestore

Banco `(default)`, modo nativo, em `southamerica-east1`, com PITR, proteção
contra exclusão e backup diário com retenção de 7 dias.

| Coleção | Escrita por | Chave |
|---|---|---|
| `volunteers` | volunteer-service | `volunteer_id` |
| `donation_notifications` | notification-service | `event_id` |

O backup gerenciado do Firestore só restaura na própria região. Por isso um
job do Cloud Scheduler chama `exportDocuments` todo dia (fuso
America/Sao_Paulo) e grava em `gs://<bucket-de-dr>/firestore`, com uma SA
própria (`datastore.importExportAdmin` no projeto, `objectAdmin` no bucket).

## Bucket de DR

Em `southamerica-west1`, com acesso público bloqueado, versionamento e
ciclo de vida (Nearline depois de 30 dias, exclusão depois de 120). Guarda
os backups do Velero (`velero/`) e os exports do Firestore (`firestore/`).

## Ambiente local

O `docker-compose.yml` reproduz o mesmo desenho com Postgres 15 e os
emuladores oficiais (imagem `google-cloud-cli:591.0.0-emulators` fixada por
digest). O `scripts/local/pubsub-init.sh` cria tópico, assinatura e DLQ no
emulador, com 5 tentativas em vez de 10 para o teste ser rápido.
