import os
import sys
import json
import time
import atexit
import logging
import threading
from flask import Flask, request, jsonify, g
from dotenv import load_dotenv
from opentelemetry import trace, propagate, metrics
from opentelemetry.trace import SpanKind, Status, StatusCode

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

load_dotenv()

app = Flask(__name__)

# --- OpenTelemetry (tracer/meter manuais) ---
# O consumidor da fila roda fora do ciclo de request/response do Flask,
# então NÃO é coberto pela auto-instrumentação (opentelemetry-instrument,
# habilitada no Dockerfile). Por isso extraímos manualmente o trace context
# propagado pelo donation-service nos atributos da mensagem e criamos um
# span filho, fechando o Distributed Trace completo até aqui.
_tracer = trace.get_tracer("notification-service")
_meter = metrics.get_meter("notification-service")

# Mesmos limites do donation-service (Go), para os percentis serem
# comparáveis entre serviços.
HTTP_DURATION_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]

_http_requests_counter = _meter.create_counter(
    "solidarytech_http_requests_total",
    description="Total de requisições HTTP recebidas, por método/rota/status",
)
_http_duration_histogram = _meter.create_histogram(
    "solidarytech_http_request_duration_seconds",
    description="Duração das requisições HTTP, em segundos",
    unit="s",
    explicit_bucket_boundaries_advisory=HTTP_DURATION_BUCKETS,
)
_messages_processed_counter = _meter.create_counter(
    "solidarytech_messages_processed_total",
    description="Total de eventos de doação processados pelo notification-service",
)


@app.before_request
def _start_timer():
    g._request_start = time.time()


@app.after_request
def _record_request_metric(response):
    elapsed = time.time() - getattr(g, "_request_start", time.time())
    attrs = {
        "service_name": "notification-service",
        "http_method": request.method,
        "http_route": request.path,
        "http_status_code": str(response.status_code),
    }
    _http_requests_counter.add(1, attrs)
    _http_duration_histogram.record(elapsed, attrs)
    return response


# --- Configuração, selecionada por CLOUD_PROVIDER ---
#   gcp   (padrão) Pub/Sub (assinatura PUBSUB_SUBSCRIPTION) -> Firestore
#                  (coleção FIRESTORE_COLLECTION). Com PUBSUB_EMULATOR_HOST e
#                  FIRESTORE_EMULATOR_HOST, fala com os emuladores locais.
#   azure          Service Bus (fila AZURE_SERVICEBUS_QUEUE_NAME) -> Cosmos DB
#                  Table API (tabela AZURE_COSMOSDB_TABLE_NAME).
# NOTIFICATION_CONSUMER_ENABLED=false sobe só o HTTP, sem consumir a fila
# (usado nos testes).
CLOUD_PROVIDER = os.getenv("CLOUD_PROVIDER", "gcp")
CONSUMER_ENABLED = os.getenv("NOTIFICATION_CONSUMER_ENABLED", "true").lower() == "true"

if CLOUD_PROVIDER == "gcp":
    GCP_PROJECT_ID = os.getenv("GCP_PROJECT_ID")
    PUBSUB_SUBSCRIPTION = os.getenv("PUBSUB_SUBSCRIPTION", "notification-service")
    FIRESTORE_DATABASE = os.getenv("FIRESTORE_DATABASE", "(default)")
    FIRESTORE_COLLECTION = os.getenv("FIRESTORE_COLLECTION", "donation_notifications")
    if not GCP_PROJECT_ID:
        log.critical("Erro: GCP_PROJECT_ID não definida.")
        sys.exit(1)
elif CLOUD_PROVIDER == "azure":
    AZURE_SERVICEBUS_CONNECTION_STRING = os.getenv("AZURE_SERVICEBUS_CONNECTION_STRING")
    AZURE_SERVICEBUS_QUEUE_NAME = os.getenv("AZURE_SERVICEBUS_QUEUE_NAME", "donation-events")
    AZURE_COSMOSDB_CONNECTION_STRING = os.getenv("AZURE_COSMOSDB_CONNECTION_STRING")
    AZURE_COSMOSDB_TABLE_NAME = os.getenv("AZURE_COSMOSDB_TABLE_NAME", "DonationNotifications")
    if not AZURE_SERVICEBUS_CONNECTION_STRING or not AZURE_COSMOSDB_CONNECTION_STRING:
        log.critical(
            "Erro: AZURE_SERVICEBUS_CONNECTION_STRING e "
            "AZURE_COSMOSDB_CONNECTION_STRING devem ser definidas."
        )
        sys.exit(1)
else:
    log.critical(f"Erro: CLOUD_PROVIDER inválido: {CLOUD_PROVIDER!r} (use gcp ou azure).")
    sys.exit(1)


def _metric(status):
    _messages_processed_counter.add(1, {"service_name": "notification-service", "status": status})


def build_record(body, event_id):
    """Monta o registro de notificação a partir do evento de doação."""
    return {
        "event_id": event_id,
        "donation_id": body["id"],
        "ngo_id": body["ngo_id"],
        "amount": body["amount"],
        "donor_name": body["donor_name"],
        "status": body["status"],
        "created_at": body.get("created_at"),
        "processed_at": str(int(time.time())),
    }


def handle_event(store, payload, attributes):
    """Processa um evento de doação e grava o registro com `store`.

    Devolve True quando gravou (a mensagem pode ser confirmada) e False
    quando não (a mensagem volta para a fila; depois de várias tentativas, o
    Pub/Sub a move para a DLQ). A chave do registro é o event_id da
    mensagem, então uma reentrega sobrescreve o mesmo registro em vez de
    duplicar. Mensagens antigas sem event_id usam o id da doação.
    """
    ctx = propagate.extract(attributes)
    with _tracer.start_as_current_span(
        "notification.process_event", context=ctx, kind=SpanKind.CONSUMER
    ) as span:
        span.set_attribute("messaging.system", "gcp_pubsub" if CLOUD_PROVIDER == "gcp" else "azure_servicebus")
        try:
            body = json.loads(payload)
            event_id = attributes.get("event_id") or f"donation-{body['id']}"
            span.set_attribute("solidarytech.donation_id", body["id"])
            span.set_attribute("solidarytech.ngo_id", body["ngo_id"])
            store(build_record(body, event_id))
        except (ValueError, KeyError, TypeError) as e:
            log.error(f"Evento de doação inválido (vai para a DLQ após as tentativas): {e}")
            span.set_status(Status(StatusCode.ERROR))
            _metric("invalid")
            return False
        except Exception as e:
            log.error(f"Erro ao gravar a notificação (a mensagem volta para a fila): {e}")
            span.set_status(Status(StatusCode.ERROR))
            span.record_exception(e)
            _metric("error")
            return False

        log.info(f"Notificação {event_id} da doação {body['id']} (NGO {body['ngo_id']}) processada.")
        _metric("success")
        return True


# --- Consumidor GCP: Pub/Sub -> Firestore ---

def make_gcp_callback(store):
    """Callback do streaming pull: confirma só depois de gravar."""
    def callback(message):
        if handle_event(store, message.data, dict(message.attributes)):
            message.ack()
        else:
            message.nack()
    return callback


def start_gcp_consumer():
    from google.cloud import firestore, pubsub_v1

    db = firestore.Client(project=GCP_PROJECT_ID, database=FIRESTORE_DATABASE)
    collection = db.collection(FIRESTORE_COLLECTION)

    def store(record):
        collection.document(record["event_id"]).set(record)

    subscriber = pubsub_v1.SubscriberClient()
    path = subscriber.subscription_path(GCP_PROJECT_ID, PUBSUB_SUBSCRIPTION)
    # Poucas mensagens em voo por pod: o processamento é uma escrita só, e
    # isso mantém a memória do pod baixa.
    future = subscriber.subscribe(
        path,
        callback=make_gcp_callback(store),
        flow_control=pubsub_v1.types.FlowControl(max_messages=10),
    )
    atexit.register(future.cancel)
    log.info(f"Consumindo {path} -> Firestore {FIRESTORE_COLLECTION}.")
    return future


# --- Consumidor Azure: Service Bus -> Cosmos DB Table API ---

def azure_entity(record):
    """Entidade do Cosmos: PartitionKey = ngo_id, RowKey = event_id."""
    entity = {"PartitionKey": str(record["ngo_id"]), "RowKey": record["event_id"]}
    entity.update({k: v for k, v in record.items() if v is not None})
    return entity


def _service_bus_attributes(message):
    raw = message.application_properties or {}
    return {
        (k.decode() if isinstance(k, bytes) else str(k)): (v.decode() if isinstance(v, bytes) else str(v))
        for k, v in raw.items()
    }


def start_azure_consumer():
    from azure.servicebus import ServiceBusClient
    from azure.data.tables import TableServiceClient

    sb_client = ServiceBusClient.from_connection_string(AZURE_SERVICEBUS_CONNECTION_STRING)
    table_client = TableServiceClient.from_connection_string(
        AZURE_COSMOSDB_CONNECTION_STRING
    ).get_table_client(AZURE_COSMOSDB_TABLE_NAME)

    def store(record):
        table_client.upsert_entity(entity=azure_entity(record))

    def loop():
        log.info(f"Consumindo a fila {AZURE_SERVICEBUS_QUEUE_NAME} do Service Bus...")
        while True:
            try:
                with sb_client.get_queue_receiver(queue_name=AZURE_SERVICEBUS_QUEUE_NAME, max_wait_time=20) as receiver:
                    for message in receiver:
                        if handle_event(store, str(message), _service_bus_attributes(message)):
                            receiver.complete_message(message)
                        else:
                            receiver.abandon_message(message)
            except Exception as e:
                log.error(f"Erro no loop do Service Bus: {e}")
                time.sleep(10)

    thread = threading.Thread(target=loop, daemon=True)
    thread.start()
    return thread


# --- Ciclo de vida do consumidor ---

_consumer = None


def start_consumer():
    """Inicia o consumidor em segundo plano. Roda dentro de cada worker do
    gunicorn depois do fork (sem --preload), então os clientes gRPC não são
    compartilhados entre processos."""
    global _consumer
    _consumer = start_gcp_consumer() if CLOUD_PROVIDER == "gcp" else start_azure_consumer()


def consumer_alive():
    if _consumer is None:
        return False
    if hasattr(_consumer, "done"):  # StreamingPullFuture do Pub/Sub
        return not _consumer.done()
    return _consumer.is_alive()  # thread do Service Bus


@app.route('/health')
def health():
    # Se o consumidor parou, a liveness probe reinicia o pod.
    if CONSUMER_ENABLED and not consumer_alive():
        return jsonify({"status": "degraded", "service": "notification-service", "consumer": "parado"}), 503
    return jsonify({"status": "ok", "service": "notification-service"})


if CONSUMER_ENABLED:
    start_consumer()

if __name__ == '__main__':
    port = int(os.getenv("PORT", 8084))
    app.run(host='0.0.0.0', port=port, debug=False)
