# ADR 0004. Pub/Sub com DLQ, ack depois de gravar e idempotência por event_id

Status: aceita (branch-gcp)

## Contexto

Na `main`, o notification-service confirmava (`complete`) a mensagem do
Service Bus sempre, mesmo quando a gravação no Cosmos DB falhava: uma falha
de banco perdia a notificação. Pub/Sub entrega pelo menos uma vez, então a
mesma mensagem pode chegar duas vezes.

## Decisão

- Tópico `donation-events`, assinatura `notification-service` (ack deadline
  de 60 s, retry de 10 s a 600 s) e DLQ `donation-events-dlq` depois de 10
  tentativas, o mesmo limite do `max_delivery_count` da versão Azure
  (`infra/terraform/modules/data/main.tf`). A DLQ tem a assinatura
  `donation-events-dlq-inspecao`, sem a qual o que cai nela se perde, e um
  alerta do Cloud Monitoring quando há mensagem parada.
- O agente de serviço do Pub/Sub recebe publisher na DLQ e subscriber na
  assinatura de origem, que é o que ele precisa para mover a mensagem.
- O donation-service gera um `event_id` (UUID) por evento e o envia como
  atributo, junto com o contexto de trace (`services/donation-service/queue.go`).
- O notification-service só dá ack depois de gravar; em erro ou JSON
  inválido dá nack, e o Pub/Sub tenta de novo até a DLQ
  (`make_gcp_callback` em `services/notification-service/app.py`). O
  documento no Firestore usa o `event_id` como chave, então reprocessar a
  mesma mensagem sobrescreve o mesmo documento em vez de duplicar. Mensagens
  antigas sem `event_id` usam `donation-<id>`.
- No caminho Azure, a mesma regra: `complete` depois de gravar, `abandon` no
  erro.

## Consequências

- Nenhuma mensagem é perdida por falha transitória do Firestore.
- O publisher do donation-service não bloqueia a resposta HTTP: publica e
  registra o resultado em segundo plano; no desligamento, `Close` espera os
  envios pendentes antes de fechar o cliente (`pubsub.go`).
- A DLQ foi testada no emulador pelo `scripts/smoke-local.sh` (mensagem
  inválida chega à `donation-events-dlq-inspecao`), com 5 tentativas no
  ambiente local (`scripts/local/pubsub-init.sh`). No Pub/Sub real, as 10
  tentativas e o papel do agente de serviço estão marcados como validado na
  nuvem: pendente.
