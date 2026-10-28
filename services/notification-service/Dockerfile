# Build stage
FROM python:3.12-slim AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Runtime stage
FROM python:3.12-slim

WORKDIR /app

COPY --from=builder /install /usr/local
COPY . .

# Descobre e instala automaticamente as bibliotecas de instrumentação OTel
# compatíveis com o que está instalado (Flask, requests etc.).
RUN opentelemetry-bootstrap -a install

# Sem root: os pacotes já estão instalados; o processo roda com um
# usuário sem privilégios.
RUN useradd --create-home --uid 10001 app
USER 10001

EXPOSE 8084

# Sem --preload: o worker consumidor da fila (start_worker) é iniciado na
# importação do módulo, dentro de cada worker gunicorn pós-fork — mesmo
# comportamento do analytics-service da Fase 3/4.
CMD ["opentelemetry-instrument", "gunicorn", "--bind", "0.0.0.0:8084", "app:app"]
