#!/bin/sh
# Cria no emulador do Pub/Sub o mesmo desenho do Terraform
# (infra/terraform/modules/data): tópico de eventos, assinatura do
# notification-service com retry e DLQ, e a assinatura de inspeção da DLQ.
# A única diferença é o número de tentativas antes da DLQ: 5 aqui (o mínimo
# permitido), 10 na nuvem, para o teste local não demorar.
set -eu

API="http://${PUBSUB_EMULATOR_HOST:?}/v1/projects/${GCP_PROJECT_ID:?}"
T="projects/${GCP_PROJECT_ID}/topics"

put() {
  body="${2:-}"
  [ -n "$body" ] || body='{}'
  curl -fsS -X PUT -H "Content-Type: application/json" -d "$body" "$API/$1" >/dev/null
  echo "criado: $1"
}

put topics/donation-events
put topics/donation-events-dlq
put subscriptions/notification-service "{
  \"topic\": \"$T/donation-events\",
  \"ackDeadlineSeconds\": 60,
  \"retryPolicy\": {\"minimumBackoff\": \"1s\", \"maximumBackoff\": \"5s\"},
  \"deadLetterPolicy\": {\"deadLetterTopic\": \"$T/donation-events-dlq\", \"maxDeliveryAttempts\": 5}
}"
put subscriptions/donation-events-dlq-inspecao "{\"topic\": \"$T/donation-events-dlq\"}"
