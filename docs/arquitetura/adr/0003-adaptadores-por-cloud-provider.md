# ADR 0003. Adaptadores por CLOUD_PROVIDER, com gcp como padrão

Status: aceita (branch-gcp)

## Contexto

Três serviços falam com mensageria ou banco NoSQL gerenciado: o
donation-service publica eventos, o notification-service consome esses
eventos e grava o resultado, e o volunteer-service guarda voluntários. Na
`main` havia caminhos Azure e, em dois serviços, também AWS (SQS e
DynamoDB) que nunca foram usados no deploy.

## Decisão

Cada serviço escolhe o backend pela variável `CLOUD_PROVIDER`:

| Serviço | `gcp` (padrão) | `azure` | outro valor |
|---|---|---|---|
| donation-service (`main.go`, `buildMessageSender`) | Pub/Sub (`pubsub.go`) | Service Bus (`servicebus.go`) | `none` desliga a mensageria; qualquer outro valor encerra com erro |
| volunteer-service (`app.py`) | Firestore, coleção `volunteers` | Cosmos DB Table | encerra com `sys.exit(1)` |
| notification-service (`app.py`) | Pub/Sub -> Firestore `donation_notifications` | Service Bus -> Cosmos DB Table | encerra com erro |

O ngo-service usa só PostgreSQL e não tem seletor.

Os caminhos AWS saíram: o donation-service usava o aws-sdk-go v1, que está
sem suporte, e nenhum manifesto ou IaC criava SQS ou DynamoDB.

## Consequências

- Um valor errado de `CLOUD_PROVIDER` derruba o pod na subida (falha rápida)
  em vez de rodar sem mensageria.
- O GitOps da `branch-gcp` fixa `CLOUD_PROVIDER=gcp`
  (`deploy/gitops/apps/*/base/deployment.yaml`), e o `docker-compose.yml`
  também, com os emuladores.
- Os testes cobrem os dois caminhos: `services/donation-service/main_test.go`
  (seleção), `pubsub_test.go` (Pub/Sub em memória com `pstest`),
  `services/volunteer-service/test_app.py` (9 testes) e
  `services/notification-service/test_app.py` (15 testes).
