package main

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"cloud.google.com/go/pubsub/v2"
	"cloud.google.com/go/pubsub/v2/apiv1/pubsubpb"
	"cloud.google.com/go/pubsub/v2/pstest"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
	"google.golang.org/api/option"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

const testProject = "solidarytech-test"

// fakePubSub sobe o servidor Pub/Sub em memória da própria biblioteca e
// cria o tópico, devolvendo as opções de conexão para os clientes.
func fakePubSub(t *testing.T, topic string) (*pstest.Server, []option.ClientOption) {
	t.Helper()
	srv := pstest.NewServer()
	t.Cleanup(func() { _ = srv.Close() })

	opts := []option.ClientOption{
		option.WithEndpoint(srv.Addr),
		option.WithoutAuthentication(),
		option.WithGRPCDialOption(grpc.WithTransportCredentials(insecure.NewCredentials())),
	}
	ctx := context.Background()
	admin, err := pubsub.NewClient(ctx, testProject, opts...)
	if err != nil {
		t.Fatalf("cliente admin: %v", err)
	}
	defer func() { _ = admin.Close() }()
	if _, err := admin.TopicAdminClient.CreateTopic(ctx, &pubsubpb.Topic{
		Name: "projects/" + testProject + "/topics/" + topic,
	}); err != nil {
		t.Fatalf("criar tópico: %v", err)
	}
	return srv, opts
}

func TestPubSubSender_PublicaEventoComTraceEEventID(t *testing.T) {
	srv, opts := fakePubSub(t, "donation-events")
	ctx := context.Background()

	otel.SetTextMapPropagator(propagation.TraceContext{})
	sc := trace.NewSpanContext(trace.SpanContextConfig{
		TraceID:    trace.TraceID{1, 2, 3},
		SpanID:     trace.SpanID{4, 5, 6},
		TraceFlags: trace.FlagsSampled,
	})
	msgCtx := trace.ContextWithSpanContext(ctx, sc)

	sender, err := NewPubSubSender(ctx, testProject, "donation-events", opts...)
	if err != nil {
		t.Fatalf("NewPubSubSender: %v", err)
	}
	d := Donation{ID: 7, NgoID: 2, Amount: 50, DonorName: "Ana", Status: "APPROVED"}
	if err := sender.SendEvent(msgCtx, d); err != nil {
		t.Fatalf("SendEvent: %v", err)
	}
	// Close precisa enviar o que estiver pendente.
	if err := sender.Close(ctx); err != nil {
		t.Fatalf("Close: %v", err)
	}

	msgs := srv.Messages()
	if len(msgs) != 1 {
		t.Fatalf("esperava 1 mensagem publicada, veio %d", len(msgs))
	}
	var got Donation
	if err := json.Unmarshal(msgs[0].Data, &got); err != nil {
		t.Fatalf("corpo não é JSON de Donation: %v", err)
	}
	if got.ID != 7 || got.NgoID != 2 || got.DonorName != "Ana" {
		t.Errorf("corpo inesperado: %+v", got)
	}
	if !strings.Contains(msgs[0].Attributes["traceparent"], sc.TraceID().String()) {
		t.Errorf("traceparent não propagado: %q", msgs[0].Attributes["traceparent"])
	}
	if msgs[0].Attributes["event_id"] == "" {
		t.Error("event_id ausente nos atributos")
	}
}

func TestPubSubSender_EventIDsDistintos(t *testing.T) {
	srv, opts := fakePubSub(t, "donation-events")
	ctx := context.Background()

	sender, err := NewPubSubSender(ctx, testProject, "donation-events", opts...)
	if err != nil {
		t.Fatalf("NewPubSubSender: %v", err)
	}
	for i := 1; i <= 3; i++ {
		if err := sender.SendEvent(ctx, Donation{ID: i, NgoID: 1}); err != nil {
			t.Fatalf("SendEvent %d: %v", i, err)
		}
	}
	if err := sender.Close(ctx); err != nil {
		t.Fatalf("Close: %v", err)
	}

	vistos := map[string]bool{}
	for _, m := range srv.Messages() {
		vistos[m.Attributes["event_id"]] = true
	}
	if len(vistos) != 3 {
		t.Errorf("esperava 3 event_id distintos, veio %d", len(vistos))
	}
}
