import os
import sys
import json
import time
import uuid
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
# O worker de fila roda numa thread própria, fora do ciclo de
# request/response do Flask, então NÃO é coberto pela auto-instrumentação
# (opentelemetry-instrument, habilitada no Dockerfile). Por isso extraímos
# manualmente o trace context propagado pelo donation-service nas
# propriedades da mensagem do Service Bus e criamos um span filho,
# fechando o Distributed Trace completo até aqui — mesmo padrão do
# analytics-service da Fase 3/4.
_tracer = trace.get_tracer("notification-service")
_meter = metrics.get_meter("notification-service")
_http_requests_counter = _meter.create_counter(
    "solidarytech_http_requests_total",
    description="Total de requisições HTTP recebidas, por método/rota/status",
)
_http_duration_histogram = _meter.create_histogram(
    "solidarytech_http_request_duration_seconds",
    description="Duração das requisições HTTP, em segundos",
    unit="s",
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


# --- Configuração ---
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


def init_clients():
    """Inicializa os clientes do Service Bus (consumidor) e do Cosmos DB
    Table API (gravação dos registros processados)."""
    from azure.servicebus import ServiceBusClient
    from azure.data.tables import TableServiceClient

    sb_client = ServiceBusClient.from_connection_string(AZURE_SERVICEBUS_CONNECTION_STRING)
    table_service = TableServiceClient.from_connection_string(AZURE_COSMOSDB_CONNECTION_STRING)
    table_client = table_service.get_table_client(AZURE_COSMOSDB_TABLE_NAME)

    log.info("Clientes Azure (Service Bus + Cosmos DB Table) inicializados.")
    return sb_client, table_client


def _extract_trace_context(carrier):
    """Reconstrói o SpanContext propagado pelo donation-service a partir
    das propriedades da mensagem (padrão W3C traceparent)."""
    return propagate.extract(carrier)


def process_message(table_client, message):
    """Processa um evento de doação recebido do Service Bus e grava o
    registro de notificação no Cosmos DB Table API."""
    raw_props = message.application_properties or {}
    carrier = {
        (k.decode() if isinstance(k, bytes) else str(k)):
        (v.decode() if isinstance(v, bytes) else str(v))
        for k, v in raw_props.items()
    }
    ctx = _extract_trace_context(carrier)

    with _tracer.start_as_current_span(
        "notification.process_event", context=ctx, kind=SpanKind.CONSUMER
    ) as span:
        try:
            body = json.loads(str(message))
            notification_id = str(uuid.uuid4())
            span.set_attribute("messaging.system", "azure_servicebus")
            span.set_attribute("solidarytech.donation_id", body.get("id", ""))
            span.set_attribute("solidarytech.ngo_id", body.get("ngo_id", ""))

            entity = {
                "PartitionKey": str(body["ngo_id"]),
                "RowKey": notification_id,
                "donation_id": body["id"],
                "ngo_id": body["ngo_id"],
                "amount": body["amount"],
                "donor_name": body["donor_name"],
                "status": body["status"],
                "processed_at": str(int(time.time())),
            }
            table_client.create_entity(entity=entity)
            log.info(
                f"Notificação {notification_id} da doação {body.get('id')} "
                f"(NGO {body.get('ngo_id')}) processada com sucesso."
            )
            _messages_processed_counter.add(1, {"service_name": "notification-service", "status": "success"})
        except json.JSONDecodeError:
            log.error("Erro ao decodificar JSON da mensagem do Service Bus.")
            span.set_status(Status(StatusCode.ERROR))
            _messages_processed_counter.add(1, {"service_name": "notification-service", "status": "error"})
        except Exception as e:
            log.error(f"Erro ao processar mensagem do Service Bus: {e}")
            span.set_status(Status(StatusCode.ERROR))
            span.record_exception(e)
            _messages_processed_counter.add(1, {"service_name": "notification-service", "status": "error"})


def worker_loop(sb_client, table_client):
    """Loop principal do worker consumidor do Service Bus."""
    log.info(f"Iniciando o worker do Service Bus (fila: {AZURE_SERVICEBUS_QUEUE_NAME})...")
    while True:
        try:
            with sb_client.get_queue_receiver(queue_name=AZURE_SERVICEBUS_QUEUE_NAME, max_wait_time=20) as receiver:
                for message in receiver:
                    process_message(table_client, message)
                    receiver.complete_message(message)
        except Exception as e:
            log.error(f"Erro no loop do Service Bus: {e}")
            time.sleep(10)


def start_worker():
    """Inicia o worker consumidor numa thread separada (não bloqueia o
    Flask, que continua respondendo /health normalmente)."""
    sb_client, table_client = init_clients()
    worker_thread = threading.Thread(target=worker_loop, args=(sb_client, table_client), daemon=True)
    worker_thread.start()


@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "notification-service"})


start_worker()

if __name__ == '__main__':
    port = int(os.getenv("PORT", 8084))
    app.run(host='0.0.0.0', port=port, debug=False)
