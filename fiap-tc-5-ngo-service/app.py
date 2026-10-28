import os
import sys
import time
import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2.pool import SimpleConnectionPool
from flask import Flask, request, jsonify, g
from dotenv import load_dotenv
from opentelemetry import metrics
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

load_dotenv()

app = Flask(__name__)

# --- Métricas customizadas (OpenTelemetry) ---
# Complementa a auto-instrumentação (habilitada via `opentelemetry-instrument`
# no Dockerfile) com um contador + histograma de nomes estáveis, usados no
# dashboard "SolidaryTech - Overview" e no dashboard SRE do Grafana.
_meter = metrics.get_meter("ngo-service")
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
        "service_name": "ngo-service",
        "http_method": request.method,
        "http_route": request.path,
        "http_status_code": str(response.status_code),
    }
    _http_requests_counter.add(1, attrs)
    _http_duration_histogram.record(elapsed, attrs)
    return response


DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    log.critical("Erro: DATABASE_URL não definida.")
    sys.exit(1)

try:
    pool = SimpleConnectionPool(1, 10, dsn=DATABASE_URL)
    log.info("Pool de conexões com o PostgreSQL (ngo-service) inicializado.")
except Exception as e:
    log.critical(f"Erro ao conectar ao PostgreSQL: {e}")
    sys.exit(1)


@app.route('/health')
def health():
    return jsonify({"status": "ok", "service": "ngo-service"})


@app.route('/ngos', methods=['POST'])
def create_ngo():
    data = request.get_json()
    if not data or not all(k in data for k in ('name', 'email', 'cause', 'city')):
        return jsonify({"error": "Campos obrigatórios ausentes"}), 400

    conn = pool.getconn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "INSERT INTO ngos (name, email, cause, city) VALUES (%s, %s, %s, %s) RETURNING *",
                (data['name'], data['email'], data['cause'], data['city'])
            )
            new_ngo = cur.fetchone()
            conn.commit()
            return jsonify(new_ngo), 201
    except psycopg2.IntegrityError:
        conn.rollback()
        return jsonify({"error": "E-mail já cadastrado"}), 409
    except Exception as e:
        conn.rollback()
        log.error(f"Erro ao criar ONG: {e}")
        return jsonify({"error": "Erro interno"}), 500
    finally:
        pool.putconn(conn)


@app.route('/ngos', methods=['GET'])
def get_ngos():
    conn = pool.getconn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT * FROM ngos ORDER BY id DESC")
            return jsonify(cur.fetchall()), 200
    except Exception as e:
        log.error(f"Erro ao buscar ONGs: {e}")
        return jsonify({"error": "Erro interno"}), 500
    finally:
        pool.putconn(conn)


if __name__ == '__main__':
    port = int(os.getenv("PORT", 8081))
    app.run(host='0.0.0.0', port=port)
