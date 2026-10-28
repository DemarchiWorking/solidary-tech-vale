import os
import sys
import time
import uuid
import logging
from flask import Flask, request, jsonify, g
from dotenv import load_dotenv
from opentelemetry import metrics

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

load_dotenv()

app = Flask(__name__)

# --- Métricas customizadas (OpenTelemetry) ---
# Complementa a auto-instrumentação (habilitada via `opentelemetry-instrument`
# no Dockerfile) com um contador + histograma de nomes estáveis, usados no
# dashboard "SolidaryTech - Overview" do Grafana. Os limites do histograma
# são os mesmos do donation-service (Go), para os percentis serem
# comparáveis entre serviços.
HTTP_DURATION_BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]

_meter = metrics.get_meter("volunteer-service")
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


@app.before_request
def _start_timer():
    g._request_start = time.time()


@app.after_request
def _record_request_metric(response):
    elapsed = time.time() - getattr(g, "_request_start", time.time())
    attrs = {
        "service_name": "volunteer-service",
        "http_method": request.method,
        "http_route": request.path,
        "http_status_code": str(response.status_code),
    }
    _http_requests_counter.add(1, attrs)
    _http_duration_histogram.record(elapsed, attrs)
    return response


# --- Armazenamento NoSQL, selecionado por CLOUD_PROVIDER ---
#   gcp   (padrão) Firestore: GCP_PROJECT_ID obrigatória; coleção
#                  FIRESTORE_COLLECTION (volunteers), com o volunteer_id como
#                  ID do documento. Com FIRESTORE_EMULATOR_HOST definido, a
#                  biblioteca fala com o emulador local (docker-compose).
#   azure          Cosmos DB Table API: PartitionKey = ngo_id, RowKey =
#                  volunteer_id.
# Qualquer outro valor encerra o processo: melhor falhar no início do que
# subir sem onde gravar.
CLOUD_PROVIDER = os.getenv("CLOUD_PROVIDER", "gcp")

if CLOUD_PROVIDER == "gcp":
    from google.cloud import firestore
    from google.cloud.firestore_v1.base_query import FieldFilter

    GCP_PROJECT_ID = os.getenv("GCP_PROJECT_ID")
    FIRESTORE_DATABASE = os.getenv("FIRESTORE_DATABASE", "(default)")
    FIRESTORE_COLLECTION = os.getenv("FIRESTORE_COLLECTION", "volunteers")

    if not GCP_PROJECT_ID:
        log.critical("Erro: GCP_PROJECT_ID não definida.")
        sys.exit(1)

    try:
        _db = firestore.Client(project=GCP_PROJECT_ID, database=FIRESTORE_DATABASE)
        log.info(f"Firestore pronto (projeto {GCP_PROJECT_ID}, coleção {FIRESTORE_COLLECTION}).")
    except Exception as e:
        log.critical(f"Falha ao inicializar o Firestore: {e}")
        sys.exit(1)

    def put_volunteer(item):
        """Grava o voluntário com o volunteer_id como ID do documento."""
        _db.collection(FIRESTORE_COLLECTION).document(item["volunteer_id"]).set(item)

    def get_volunteers_by_ngo(ngo_id):
        """Consulta por ngo_id (índice de campo único, criado
        automaticamente pelo Firestore)."""
        query = _db.collection(FIRESTORE_COLLECTION).where(filter=FieldFilter("ngo_id", "==", ngo_id))
        return [doc.to_dict() for doc in query.stream()]

elif CLOUD_PROVIDER == "azure":
    from azure.data.tables import TableServiceClient

    AZURE_COSMOSDB_CONNECTION_STRING = os.getenv("AZURE_COSMOSDB_CONNECTION_STRING")
    AZURE_COSMOSDB_TABLE_NAME = os.getenv("AZURE_COSMOSDB_TABLE_NAME", "Volunteers")

    if not AZURE_COSMOSDB_CONNECTION_STRING:
        log.critical("Erro: AZURE_COSMOSDB_CONNECTION_STRING não definida.")
        sys.exit(1)

    try:
        _table_service = TableServiceClient.from_connection_string(AZURE_COSMOSDB_CONNECTION_STRING)
        _table_client = _table_service.get_table_client(AZURE_COSMOSDB_TABLE_NAME)
        log.info(f"Conectado à tabela Cosmos DB (Table API): {AZURE_COSMOSDB_TABLE_NAME}")
    except Exception as e:
        log.critical(f"Falha ao conectar no Cosmos DB: {e}")
        sys.exit(1)

    def put_volunteer(item):
        """Grava o voluntário no Cosmos DB Table API.

        PartitionKey = ngo_id (consulta eficiente por ONG via filtro de
        partição); RowKey = volunteer_id.
        """
        entity = {
            "PartitionKey": str(item["ngo_id"]),
            "RowKey": item["volunteer_id"],
            "name": item["name"],
            "email": item["email"],
            "ngo_id": item["ngo_id"],
            "registered_at": item["registered_at"],
        }
        _table_client.create_entity(entity=entity)

    def get_volunteers_by_ngo(ngo_id):
        entities = _table_client.query_entities(f"PartitionKey eq '{ngo_id}'")
        return [
            {
                "volunteer_id": e["RowKey"],
                "name": e["name"],
                "email": e["email"],
                "ngo_id": e["ngo_id"],
                "registered_at": e["registered_at"],
            }
            for e in entities
        ]

else:
    log.critical(f"Erro: CLOUD_PROVIDER inválido: {CLOUD_PROVIDER!r} (use gcp ou azure).")
    sys.exit(1)


@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "volunteer-service"})


@app.route('/volunteers', methods=['POST'])
def register_volunteer():
    data = request.get_json(silent=True)
    if not data or not all(k in data for k in ('name', 'email', 'ngo_id')):
        return jsonify({"error": "Campos obrigatórios ausentes"}), 400

    volunteer_id = str(uuid.uuid4())
    item = {
        'volunteer_id': volunteer_id,
        'name': data['name'],
        'email': data['email'],
        'ngo_id': int(data['ngo_id']),
        'registered_at': str(int(time.time()))
    }

    try:
        put_volunteer(item)
        return jsonify(item), 201
    except Exception as e:
        log.error(f"Erro ao salvar voluntário: {e}")
        return jsonify({"error": "Erro interno ao processar dados"}), 500


@app.route('/volunteers/<int:ngo_id>', methods=['GET'])
def get_volunteers(ngo_id):
    try:
        return jsonify(get_volunteers_by_ngo(ngo_id)), 200
    except Exception as e:
        log.error(f"Erro ao buscar voluntários: {e}")
        return jsonify({"error": "Erro interno"}), 500


if __name__ == '__main__':
    port = int(os.getenv("PORT", 8083))
    app.run(host='0.0.0.0', port=port)
