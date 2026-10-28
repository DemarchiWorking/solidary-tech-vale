package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"

	"cloud.google.com/go/pubsub/v2"
	"google.golang.org/api/option"
)

// PubSubSender implementa MessageSender para o Google Cloud Pub/Sub
// (CLOUD_PROVIDER=gcp, o padrão). O Publisher é de vida longa: agrupa as
// mensagens em lotes e só precisa de Stop() no desligamento, que envia o
// que ainda estiver pendente. Com PUBSUB_EMULATOR_HOST definido, a
// biblioteca fala com o emulador local (docker-compose).
type PubSubSender struct {
	client    *pubsub.Client
	publisher *pubsub.Publisher
	pending   sync.WaitGroup
}

func NewPubSubSender(ctx context.Context, projectID, topic string, opts ...option.ClientOption) (*PubSubSender, error) {
	client, err := pubsub.NewClient(ctx, projectID, opts...)
	if err != nil {
		return nil, fmt.Errorf("erro ao criar cliente Pub/Sub: %w", err)
	}
	return &PubSubSender{client: client, publisher: client.Publisher(topic)}, nil
}

func (s *PubSubSender) SendEvent(ctx context.Context, d Donation) error {
	body, err := json.Marshal(d)
	if err != nil {
		return fmt.Errorf("erro ao serializar evento: %w", err)
	}

	// Publish não bloqueia: o resultado chega por PublishResult, que é
	// acompanhado em segundo plano só para registrar sucesso ou falha.
	result := s.publisher.Publish(ctx, &pubsub.Message{Data: body, Attributes: eventAttributes(ctx)})
	s.pending.Add(1)
	go func() {
		defer s.pending.Done()
		id, err := result.Get(context.Background())
		if err != nil {
			log.Printf("Erro ao publicar evento da doação %d no Pub/Sub: %v", d.ID, err)
			return
		}
		log.Printf("Evento de doação publicado no Pub/Sub (Donation ID: %d, mensagem %s)", d.ID, id)
	}()
	return nil
}

// Close envia o que estiver pendente e encerra o cliente. Respeita o prazo
// de ctx para não travar o desligamento do pod.
func (s *PubSubSender) Close(ctx context.Context) error {
	s.publisher.Stop()
	if err := waitWithContext(ctx, &s.pending); err != nil {
		return err
	}
	return s.client.Close()
}

// waitWithContext espera o WaitGroup ou o fim do prazo de ctx, o que vier
// primeiro.
func waitWithContext(ctx context.Context, wg *sync.WaitGroup) error {
	done := make(chan struct{})
	go func() {
		wg.Wait()
		close(done)
	}()
	select {
	case <-done:
		return nil
	case <-ctx.Done():
		return fmt.Errorf("envios pendentes não terminaram no prazo: %w", ctx.Err())
	}
}
