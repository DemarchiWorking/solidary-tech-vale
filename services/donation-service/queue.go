package main

import (
	"context"

	"github.com/google/uuid"
)

// MessageSender abstrai o envio do evento de doação para a fila. O ctx
// carrega o SpanContext da requisição HTTP original, permitindo que o span
// de mensageria fique vinculado ao mesmo trace distribuído no APM (o
// notification-service reconstrói esse trace ao consumir a mensagem).
//
// SendEvent não bloqueia a requisição: cada implementação entrega o evento
// em segundo plano. Close espera os envios pendentes terminarem — é chamado
// no desligamento, depois que o servidor HTTP para de aceitar requisições.
type MessageSender interface {
	SendEvent(ctx context.Context, d Donation) error
	Close(ctx context.Context) error
}

// eventAttributes monta os atributos da mensagem: o contexto de trace
// (traceparent/tracestate) e um event_id único, que o notification-service
// usa como chave para gravar cada evento uma vez só, mesmo com reentrega.
func eventAttributes(ctx context.Context) map[string]string {
	attrs := injectTraceContext(ctx)
	attrs["event_id"] = uuid.NewString()
	return attrs
}
