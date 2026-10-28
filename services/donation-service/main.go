package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	_ "github.com/jackc/pgx/v4/stdlib"
	"github.com/joho/godotenv"
)

// shutdownTimeout é o prazo para terminar as requisições em andamento e
// enviar os eventos pendentes. Fica abaixo do terminationGracePeriodSeconds
// do Deployment (60s) para o kubelet não matar o processo antes.
const shutdownTimeout = 25 * time.Second

func main() {
	_ = godotenv.Load()

	// SIGTERM é o que o Kubernetes manda antes de remover o pod.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// --- OpenTelemetry (traces + métricas via OTel Collector) ---
	shutdownOTel, err := initOTel(ctx)
	if err != nil {
		log.Fatalf("Não foi possível inicializar o OpenTelemetry: %v", err)
	}

	// --- Configuração ---
	port := os.Getenv("PORT")
	if port == "" {
		port = "8082"
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL é obrigatória")
	}

	db, err := sql.Open("pgx", dbURL)
	if err != nil {
		log.Fatalf("Erro ao abrir conexão com o banco de dados: %v", err)
	}
	if err := db.Ping(); err != nil {
		log.Fatalf("Erro ao conectar ao banco de dados: %v", err)
	}
	log.Println("Conectado ao PostgreSQL (donation-service).")

	// --- Mensageria: Pub/Sub (gcp, padrão) ou Service Bus (azure) ---
	msgSender, err := buildMessageSender(ctx)
	if err != nil {
		log.Fatalf("Mensageria: %v", err)
	}

	app := &App{DB: db, MsgSender: msgSender}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", app.HealthHandler)
	mux.HandleFunc("/donations", app.DonationHandler)

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           instrumentHandler(mux),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Printf("donation-service rodando na porta %s", port)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("Erro no servidor HTTP: %v", err)
		}
	}()

	<-ctx.Done()
	log.Println("Sinal de desligamento recebido: encerrando o donation-service.")

	// Ordem: para de aceitar requisições, envia os eventos pendentes e só
	// então encerra o OpenTelemetry (que ainda registra esses envios).
	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("Erro ao encerrar o servidor HTTP: %v", err)
	}
	if msgSender != nil {
		if err := msgSender.Close(shutdownCtx); err != nil {
			log.Printf("Erro ao encerrar a mensageria: %v", err)
		}
	}
	if err := shutdownOTel(shutdownCtx); err != nil {
		log.Printf("Erro ao encerrar o OpenTelemetry: %v", err)
	}
	if err := db.Close(); err != nil {
		log.Printf("Erro ao fechar o banco de dados: %v", err)
	}
	log.Println("donation-service encerrado.")
}

// buildMessageSender escolhe a mensageria por CLOUD_PROVIDER:
//
//	gcp   (padrão) Pub/Sub: GCP_PROJECT_ID obrigatória, PUBSUB_TOPIC (donation-events)
//	azure          Service Bus: AZURE_SERVICEBUS_CONNECTION_STRING e AZURE_SERVICEBUS_QUEUE_NAME
//	none           sem mensageria (a doação é gravada, mas não notificada)
//
// Qualquer outro valor é erro: melhor falhar no início do que rodar sem
// notificar as doações por um erro de digitação.
func buildMessageSender(ctx context.Context) (MessageSender, error) {
	provider := os.Getenv("CLOUD_PROVIDER")
	if provider == "" {
		provider = "gcp"
	}

	switch provider {
	case "gcp":
		projectID := os.Getenv("GCP_PROJECT_ID")
		if projectID == "" {
			return nil, errors.New("GCP_PROJECT_ID é obrigatória para CLOUD_PROVIDER=gcp")
		}
		topic := os.Getenv("PUBSUB_TOPIC")
		if topic == "" {
			topic = "donation-events"
		}
		sender, err := NewPubSubSender(ctx, projectID, topic)
		if err != nil {
			return nil, err
		}
		log.Printf("Cliente Pub/Sub inicializado (projeto %s, tópico %s).", projectID, topic)
		return sender, nil

	case "azure":
		connStr := os.Getenv("AZURE_SERVICEBUS_CONNECTION_STRING")
		queueName := os.Getenv("AZURE_SERVICEBUS_QUEUE_NAME")
		if connStr == "" || queueName == "" {
			return nil, errors.New("AZURE_SERVICEBUS_CONNECTION_STRING e AZURE_SERVICEBUS_QUEUE_NAME são obrigatórias para CLOUD_PROVIDER=azure")
		}
		sender, err := NewServiceBusSender(connStr, queueName)
		if err != nil {
			return nil, err
		}
		log.Println("Cliente Azure Service Bus inicializado com sucesso.")
		return sender, nil

	case "none":
		log.Println("Atenção: mensageria desabilitada (CLOUD_PROVIDER=none).")
		return nil, nil

	default:
		return nil, fmt.Errorf("CLOUD_PROVIDER inválido: %q (use gcp, azure ou none)", provider)
	}
}
