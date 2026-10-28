#!/usr/bin/env bash
# Teste de ponta a ponta do ambiente local (docker compose up -d --wait):
#   1. os 4 serviços respondem /health;
#   2. doação: POST /donations -> Pub/Sub -> notification-service -> Firestore;
#   3. voluntário: POST /volunteers e GET /volunteers/<ngo_id> no Firestore;
#   4. DLQ: uma mensagem inválida é recusada e chega à fila de dead-letter.
# Sai com código diferente de zero no primeiro passo que falhar.
set -euo pipefail

NGO="http://127.0.0.1:${NGO_PORT:-9081}"
DONATION="http://127.0.0.1:${DONATION_PORT:-9082}"
VOLUNTEER="http://127.0.0.1:${VOLUNTEER_PORT:-9083}"
NOTIFICATION="http://127.0.0.1:${NOTIFICATION_PORT:-9084}"
PUBSUB="http://127.0.0.1:${PUBSUB_PORT:-9085}/v1/projects/solidarytech-local"
FIRESTORE="http://127.0.0.1:${FIRESTORE_PORT:-9086}/v1/projects/solidarytech-local/databases/(default)/documents"

PY=""
for c in python3 python; do
  if "$c" -c "import sys" >/dev/null 2>&1; then PY="$c"; break; fi
done
[[ -n "$PY" ]] || { echo "precisa de python3 para ler JSON" >&2; exit 2; }

passo() { echo "-> $*"; }
falha() { echo "FALHOU: $*" >&2; exit 1; }
json() { "$PY" -c "import sys, json; d = json.load(sys.stdin); print($1)"; }

# espera(<segundos>, <comando...>): repete o comando até ele dar certo.
espera() {
  local limite=$1; shift
  for _ in $(seq 1 "$limite"); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}

passo "health dos 4 serviços"
for url in "$NGO" "$DONATION" "$VOLUNTEER" "$NOTIFICATION"; do
  curl -fsS "$url/health" >/dev/null || falha "$url/health"
done

passo "cria uma ONG"
NGO_ID=$(curl -fsS -X POST "$NGO/ngos" -H "Content-Type: application/json" \
  -d "{\"name\":\"ONG Smoke $RANDOM\",\"email\":\"smoke-$RANDOM-$RANDOM@example.org\",\"cause\":\"Educacao\",\"city\":\"Osasco\"}" \
  | json 'd["id"]') || falha "POST /ngos"

passo "registra uma doação para a ONG $NGO_ID"
DONATION_ID=$(curl -fsS -X POST "$DONATION/donations" -H "Content-Type: application/json" \
  -d "{\"ngo_id\":$NGO_ID,\"amount\":42.5,\"donor_name\":\"Smoke\"}" | json 'd["id"]') || falha "POST /donations"

notificada() {
  curl -fsS -H "Authorization: Bearer owner" "$FIRESTORE/donation_notifications?pageSize=300" \
    | json "any(doc['fields'].get('donation_id', {}).get('integerValue') == '$DONATION_ID' for doc in d.get('documents', []))" \
    | grep -q True
}
passo "espera a notificação da doação $DONATION_ID no Firestore (via Pub/Sub)"
espera 60 notificada || falha "a doação $DONATION_ID não chegou ao Firestore"

passo "registra e lista um voluntário"
VOL_ID=$(curl -fsS -X POST "$VOLUNTEER/volunteers" -H "Content-Type: application/json" \
  -d "{\"name\":\"Voluntaria Smoke\",\"email\":\"vol@example.org\",\"ngo_id\":$NGO_ID}" | json 'd["volunteer_id"]') \
  || falha "POST /volunteers"
curl -fsS "$VOLUNTEER/volunteers/$NGO_ID" | json "any(v['volunteer_id'] == '$VOL_ID' for v in d)" | grep -q True \
  || falha "GET /volunteers/$NGO_ID não trouxe $VOL_ID"

passo "publica uma mensagem inválida e espera ela chegar à DLQ"
POISON="smoke-poison-$RANDOM$RANDOM"
DATA=$(printf 'isto nao e json' | base64)
curl -fsS -X POST "$PUBSUB/topics/donation-events:publish" -H "Content-Type: application/json" \
  -d "{\"messages\":[{\"data\":\"$DATA\",\"attributes\":{\"event_id\":\"$POISON\"}}]}" >/dev/null \
  || falha "publicar no tópico"

na_dlq() {
  local resp
  resp=$(curl -fsS -X POST "$PUBSUB/subscriptions/donation-events-dlq-inspecao:pull" \
    -H "Content-Type: application/json" -d '{"maxMessages":10}')
  local acks
  acks=$(echo "$resp" | json "[m['ackId'] for m in d.get('receivedMessages', [])]")
  if [[ "$acks" != "[]" ]]; then
    curl -fsS -X POST "$PUBSUB/subscriptions/donation-events-dlq-inspecao:acknowledge" \
      -H "Content-Type: application/json" -d "{\"ackIds\":${acks//\'/\"}}" >/dev/null
  fi
  echo "$resp" | json "any(m['message'].get('attributes', {}).get('event_id') == '$POISON' for m in d.get('receivedMessages', []))" \
    | grep -q True
}
espera 90 na_dlq || falha "a mensagem inválida não chegou à DLQ"

echo "OK: doação $DONATION_ID notificada, voluntário $VOL_ID listado e DLQ funcionando."
