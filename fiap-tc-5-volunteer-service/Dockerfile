# Build stage
FROM python:3.11-slim AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Runtime stage
FROM python:3.11-slim

WORKDIR /app

COPY --from=builder /install /usr/local
COPY . .

# Descobre e instala automaticamente as bibliotecas de instrumentação OTel
# compatíveis com o que está instalado (Flask, requests etc.).
RUN opentelemetry-bootstrap -a install

# Sem root: os pacotes já estão instalados; o processo roda com um
# usuário sem privilégios.
RUN useradd --no-create-home --uid 10001 app
USER 10001

EXPOSE 8083

# Sem --preload: cada worker gunicorn importa app.py após o fork, evitando
# problemas de conexões/threads herdadas de antes do fork (lição da Fase 4).
CMD ["opentelemetry-instrument", "gunicorn", "--bind", "0.0.0.0:8083", "app:app"]
