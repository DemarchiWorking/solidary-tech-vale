# Build stage
FROM golang:1.26-alpine AS builder

WORKDIR /app

# Dependências numa camada própria: só baixa de novo quando go.mod/go.sum
# mudam. O build usa exatamente o go.sum versionado (sem go mod tidy aqui).
COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /donation-service .

# Runtime stage
FROM alpine:3.24

RUN apk --no-cache add ca-certificates \
    && adduser -D -H -u 10001 app

WORKDIR /app

COPY --from=builder /donation-service .

# Sem root: o processo roda com um usuário sem privilégios.
USER 10001

EXPOSE 8082

CMD ["./donation-service"]
