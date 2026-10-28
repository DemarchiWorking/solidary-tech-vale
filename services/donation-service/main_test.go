package main

import (
	"context"
	"strings"
	"testing"

	"cloud.google.com/go/pubsub/v2/pstest"
)

func TestBuildMessageSender_ProviderInvalidoFalha(t *testing.T) {
	t.Setenv("CLOUD_PROVIDER", "aws")
	if _, err := buildMessageSender(context.Background()); err == nil || !strings.Contains(err.Error(), "inválido") {
		t.Fatalf("esperava erro de CLOUD_PROVIDER inválido, veio %v", err)
	}
}

func TestBuildMessageSender_GCPSemProjetoFalha(t *testing.T) {
	t.Setenv("CLOUD_PROVIDER", "gcp")
	t.Setenv("GCP_PROJECT_ID", "")
	if _, err := buildMessageSender(context.Background()); err == nil || !strings.Contains(err.Error(), "GCP_PROJECT_ID") {
		t.Fatalf("esperava erro pedindo GCP_PROJECT_ID, veio %v", err)
	}
}

func TestBuildMessageSender_AzureSemConfiguracaoFalha(t *testing.T) {
	t.Setenv("CLOUD_PROVIDER", "azure")
	t.Setenv("AZURE_SERVICEBUS_CONNECTION_STRING", "")
	t.Setenv("AZURE_SERVICEBUS_QUEUE_NAME", "")
	if _, err := buildMessageSender(context.Background()); err == nil {
		t.Fatal("esperava erro sem a configuração do Service Bus")
	}
}

func TestBuildMessageSender_NoneDesligaMensageria(t *testing.T) {
	t.Setenv("CLOUD_PROVIDER", "none")
	sender, err := buildMessageSender(context.Background())
	if err != nil || sender != nil {
		t.Fatalf("esperava (nil, nil), veio (%v, %v)", sender, err)
	}
}

func TestBuildMessageSender_GCPPadraoComEmulador(t *testing.T) {
	srv := pstest.NewServer()
	t.Cleanup(func() { _ = srv.Close() })

	// Sem CLOUD_PROVIDER, o padrão é gcp; com PUBSUB_EMULATOR_HOST a
	// biblioteca conecta sem credenciais, como no docker-compose.
	t.Setenv("CLOUD_PROVIDER", "")
	t.Setenv("GCP_PROJECT_ID", testProject)
	t.Setenv("PUBSUB_EMULATOR_HOST", srv.Addr)

	sender, err := buildMessageSender(context.Background())
	if err != nil {
		t.Fatalf("buildMessageSender: %v", err)
	}
	if _, ok := sender.(*PubSubSender); !ok {
		t.Fatalf("esperava *PubSubSender, veio %T", sender)
	}
	if err := sender.Close(context.Background()); err != nil {
		t.Fatalf("Close: %v", err)
	}
}
