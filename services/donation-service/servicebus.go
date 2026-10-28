package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"

	"github.com/Azure/azure-sdk-for-go/sdk/messaging/azservicebus"
)

// ServiceBusSender implementa MessageSender para Azure Service Bus
// (CLOUD_PROVIDER=azure). Mantido ao lado do Pub/Sub para a plataforma
// poder voltar ao Azure só trocando a configuração.
type ServiceBusSender struct {
	client    *azservicebus.Client
	queueName string
	pending   sync.WaitGroup
}

func NewServiceBusSender(connectionString, queueName string) (*ServiceBusSender, error) {
	client, err := azservicebus.NewClientFromConnectionString(connectionString, nil)
	if err != nil {
		return nil, fmt.Errorf("erro ao criar cliente Service Bus: %w", err)
	}
	return &ServiceBusSender{client: client, queueName: queueName}, nil
}

// SendEvent envia em segundo plano para não prender a requisição HTTP; Close
// espera esses envios terminarem.
func (s *ServiceBusSender) SendEvent(ctx context.Context, d Donation) error {
	body, err := json.Marshal(d)
	if err != nil {
		return fmt.Errorf("erro ao serializar evento: %w", err)
	}

	// Propaga o traceparent/tracestate e o event_id como propriedades da
	// mensagem, para o notification-service reconstruir o mesmo trace e
	// gravar o evento uma vez só.
	attrs := eventAttributes(ctx)
	appProps := make(map[string]interface{}, len(attrs))
	for k, v := range attrs {
		appProps[k] = v
	}
	messageID := attrs["event_id"]

	s.pending.Add(1)
	go func() {
		defer s.pending.Done()
		if err := s.send(body, appProps, messageID); err != nil {
			log.Printf("Erro ao despachar evento da doação %d para o Service Bus: %v", d.ID, err)
			return
		}
		log.Printf("Evento de doação enviado para Service Bus (Donation ID: %d)", d.ID)
	}()
	return nil
}

func (s *ServiceBusSender) send(body []byte, appProps map[string]interface{}, messageID string) error {
	sender, err := s.client.NewSender(s.queueName, nil)
	if err != nil {
		return fmt.Errorf("erro ao criar sender: %w", err)
	}
	defer func() {
		if err := sender.Close(context.Background()); err != nil {
			log.Printf("Erro ao fechar sender do Service Bus: %v", err)
		}
	}()

	return sender.SendMessage(context.Background(), &azservicebus.Message{
		Body:                  body,
		MessageID:             &messageID,
		ApplicationProperties: appProps,
	}, nil)
}

func (s *ServiceBusSender) Close(ctx context.Context) error {
	if err := waitWithContext(ctx, &s.pending); err != nil {
		return err
	}
	return s.client.Close(ctx)
}
