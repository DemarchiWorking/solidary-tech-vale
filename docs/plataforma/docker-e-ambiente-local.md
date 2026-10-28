# Docker e ambiente local

## Imagens

| Serviço | Dockerfile | Base | Porta |
|---|---|---|---|
| ngo-service | `services/ngo-service/Dockerfile` | `python:3.12-slim` (build em dois estágios) | 8081 |
| donation-service | `services/donation-service/Dockerfile` | `golang:1.26-alpine` no build, `alpine:3.24` no runtime | 8082 |
| volunteer-service | `services/volunteer-service/Dockerfile` | `python:3.12-slim` | 8083 |
| notification-service | `services/notification-service/Dockerfile` | `python:3.12-slim` | 8084 |

Todas rodam como o usuário 10001. As Python instalam a instrumentação do
OpenTelemetry no build (`opentelemetry-bootstrap`) e sobem com gunicorn; o
usuário tem home (`useradd --create-home`), porque o gunicorn 26 grava o
socket de controle nela. O Go baixa as dependências numa camada separada e
compila um binário estático.

## Ambiente local completo

`docker-compose.yml`, na raiz, sobe o mesmo desenho da nuvem:

| Serviço do compose | No GCP equivale a | Porta no host |
|---|---|---|
| `postgres` (15-alpine, cria `ngo_db` e `donation_db` com os `db/init.sql`) | Cloud SQL | interna |
| `pubsub-emulator` | Pub/Sub | 127.0.0.1:9085 |
| `firestore-emulator` | Firestore | 127.0.0.1:9086 |
| `pubsub-init` (roda uma vez) | `modules/data` | n/a |
| `otel-collector` | OTel Collector do cluster | interna |
| `ngo-service`, `donation-service`, `volunteer-service`, `notification-service` | os Deployments | 127.0.0.1:9081 a 9084 |

Os emuladores são os oficiais do Google
(`google-cloud-cli:591.0.0-emulators`, fixado por digest). Os serviços rodam
com `CLOUD_PROVIDER=gcp` e as variáveis `PUBSUB_EMULATOR_HOST` e
`FIRESTORE_EMULATOR_HOST`, que fazem as bibliotecas do Google falarem com o
emulador sem credencial. Também rodam com as restrições do cluster:
usuário 10001, `cap_drop: [ALL]` e `no-new-privileges`. Dentro do
container, `/proc/1/status` mostra `CapEff: 0000000000000000` e
`NoNewPrivs: 1`.

Todas as portas ficam só em 127.0.0.1 e mudam por variável (`NGO_PORT`,
`DONATION_PORT`, `VOLUNTEER_PORT`, `NOTIFICATION_PORT`, `PUBSUB_PORT`,
`FIRESTORE_PORT`).

## Rodar

```bash
docker compose up -d --build --wait
```

```bash
bash scripts/smoke-local.sh
```

```bash
docker compose down -v
```

O `scripts/smoke-local.sh` testa, nesta ordem:

1. `/health` dos 4 serviços;
2. `POST /ngos`;
3. `POST /donations` e espera o documento aparecer em
   `donation_notifications` no Firestore, o que prova o caminho
   donation-service, Pub/Sub, notification-service, Firestore;
4. `POST /volunteers` e `GET /volunteers/<ngo_id>` no Firestore;
5. publica uma mensagem inválida e espera ela chegar à assinatura da DLQ.

Numa máquina com as imagens já em cache, a subida e o smoke levam menos de
1 minuto. O mesmo roteiro roda no CI pelo workflow `local-e2e.yaml`.

## Dicas

- No Windows, rode o smoke no Git Bash. Os payloads do smoke são ASCII de
  propósito: argumentos com acento passados ao `curl` pelo Windows chegam
  quebrados.
- O repositório usa LF em todo arquivo (`.gitattributes`); um script com
  CRLF quebra dentro do container.
