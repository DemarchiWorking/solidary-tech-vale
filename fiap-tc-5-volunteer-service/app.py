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
# dashboard "SolidaryTech - Overview" do Grafana.
_meter = metrics.get_meter("volunteer-service")
_http_requests_counter = _meter.create_counter(
    "solidarytech_http_requests_total",
    description="Total de requisições HTTP recebidas, por método/rota/status",
)
_http_duration_histogram = _meter.create_histogram(
    "solidarytech_http_request_duration_seconds",
    description="Duração das requisições HTTP, em segundos",
    unit="s",
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


# --- Armazenamento NoSQL: Azure Cosmos DB Table API (produção) ou AWS
# DynamoDB (dev local / LocalStack) — selecionado via CLOUD_PROVIDER, mesmo
# padrão usado no evaluation-service/analytics-service da Fase 3/4. O
# código original (só DynamoDB) foi preservado; só adicionamos o caminho
# Azure por cima.
CLOUD_PROVIDER = os.getenv("CLOUD_PROVIDER", "aws")

if CLOUD_PROVIDER == "azure":
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

        PartitionKey = ngo_id (permite consulta eficiente por ONG via
        filtro de partição, sem precisar de scan completo como no DynamoDB
        original); RowKey = volunteer_id.
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
    import boto3

    AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
    DYNAMODB_TABLE = os.getenv("AWS_DYNAMODB_TABLE")

    if not DYNAMODB_TABLE:
        log.critical("Erro: AWS_DYNAMODB_TABLE não definida.")
        sys.exit(1)

    try:
        _dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
        _table = _dynamodb.Table(DYNAMODB_TABLE)
        log.info(f"Conectado à tabela DynamoDB: {DYNAMODB_TABLE}")
    except Exception as e:
        log.critical(f"Falha ao conectar no DynamoDB: {e}")
        sys.exit(1)

    def put_volunteer(item):
        _table.put_item(Item=item)

    def get_volunteers_by_ngo(ngo_id):
        response = _table.scan(
            FilterExpression=boto3.dynamodb.conditions.Attr("ngo_id").eq(ngo_id)
        )
        return response.get("Items", [])


@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "volunteer-service"})


@app.route('/volunteers', methods=['POST'])
def register_volunteer():
    data = request.get_json()
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
