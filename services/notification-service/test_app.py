import importlib
import json
from unittest.mock import MagicMock, patch

import pytest

EVENTO = {
    "id": 1,
    "ngo_id": 2,
    "amount": 50.0,
    "donor_name": "Fulano",
    "status": "APPROVED",
    "created_at": "2026-09-10T00:00:00Z",
}


@pytest.fixture(autouse=True)
def mock_env(monkeypatch):
    monkeypatch.setenv("CLOUD_PROVIDER", "gcp")
    monkeypatch.setenv("GCP_PROJECT_ID", "solidarytech-test")
    # Sem consumidor: o import não cria clientes nem threads.
    monkeypatch.setenv("NOTIFICATION_CONSUMER_ENABLED", "false")


def load_app():
    import app as app_module
    importlib.reload(app_module)
    app_module.app.config["TESTING"] = True
    return app_module


class TestHealth:
    def test_ok_sem_consumidor(self):
        app_module = load_app()
        with app_module.app.test_client() as client:
            response = client.get("/health")
        assert response.status_code == 200
        assert json.loads(response.data)["service"] == "notification-service"

    def test_503_quando_o_consumidor_para(self):
        app_module = load_app()
        app_module.CONSUMER_ENABLED = True
        app_module._consumer = MagicMock()
        app_module._consumer.done.return_value = True  # streaming pull encerrado
        with app_module.app.test_client() as client:
            response = client.get("/health")
        assert response.status_code == 503

    def test_import_nao_cria_clientes_quando_desligado(self):
        with patch("google.cloud.pubsub_v1.SubscriberClient") as subscriber, \
                patch("google.cloud.firestore.Client") as firestore_client:
            load_app()
        subscriber.assert_not_called()
        firestore_client.assert_not_called()

    def test_import_inicia_consumidor_quando_ligado(self, monkeypatch):
        monkeypatch.setenv("NOTIFICATION_CONSUMER_ENABLED", "true")
        with patch("google.cloud.pubsub_v1.SubscriberClient") as subscriber, \
                patch("google.cloud.firestore.Client") as firestore_client:
            app_module = load_app()
        firestore_client.assert_called_once_with(project="solidarytech-test", database="(default)")
        subscriber.return_value.subscribe.assert_called_once()
        assert app_module.consumer_alive() is not None


class TestHandleEvent:
    def test_grava_com_event_id_e_campos_do_evento(self):
        app_module = load_app()
        store = MagicMock()
        ok = app_module.handle_event(store, json.dumps(EVENTO).encode(), {"event_id": "ev-123"})
        assert ok is True
        record = store.call_args.args[0]
        assert record["event_id"] == "ev-123"
        assert (record["donation_id"], record["ngo_id"], record["amount"]) == (1, 2, 50.0)
        assert record["created_at"] == "2026-09-10T00:00:00Z"

    def test_sem_event_id_usa_o_id_da_doacao(self):
        app_module = load_app()
        store = MagicMock()
        assert app_module.handle_event(store, json.dumps(EVENTO), {}) is True
        assert store.call_args.args[0]["event_id"] == "donation-1"

    def test_json_invalido_nao_grava(self):
        app_module = load_app()
        store = MagicMock()
        assert app_module.handle_event(store, b"not-json", {}) is False
        store.assert_not_called()

    def test_campo_obrigatorio_ausente_nao_grava(self):
        app_module = load_app()
        store = MagicMock()
        incompleto = {k: v for k, v in EVENTO.items() if k != "ngo_id"}
        assert app_module.handle_event(store, json.dumps(incompleto), {}) is False
        store.assert_not_called()

    def test_falha_na_gravacao_devolve_false(self):
        app_module = load_app()
        store = MagicMock(side_effect=RuntimeError("Firestore indisponível"))
        assert app_module.handle_event(store, json.dumps(EVENTO), {"event_id": "ev-1"}) is False


class TestCallbackPubSub:
    def _mensagem(self, data, attributes):
        message = MagicMock()
        message.data = data
        message.attributes = attributes
        return message

    def test_ack_depois_de_gravar(self):
        app_module = load_app()
        store = MagicMock()
        message = self._mensagem(json.dumps(EVENTO).encode(), {"event_id": "ev-9"})
        app_module.make_gcp_callback(store)(message)
        store.assert_called_once()
        message.ack.assert_called_once()
        message.nack.assert_not_called()

    def test_nack_quando_nao_grava(self):
        app_module = load_app()
        store = MagicMock(side_effect=RuntimeError("falhou"))
        message = self._mensagem(json.dumps(EVENTO).encode(), {})
        app_module.make_gcp_callback(store)(message)
        message.nack.assert_called_once()
        message.ack.assert_not_called()

    def test_nack_para_mensagem_invalida(self):
        app_module = load_app()
        message = self._mensagem(b"{quebrado", {})
        app_module.make_gcp_callback(MagicMock())(message)
        message.nack.assert_called_once()


class TestAzure:
    def test_entidade_do_cosmos_usa_ngo_e_event_id(self, monkeypatch):
        monkeypatch.setenv("CLOUD_PROVIDER", "azure")
        monkeypatch.setenv("AZURE_SERVICEBUS_CONNECTION_STRING", "Endpoint=sb://test/;SharedAccessKeyName=x;SharedAccessKey=y")
        monkeypatch.setenv(
            "AZURE_COSMOSDB_CONNECTION_STRING",
            "DefaultEndpointsProtocol=https;AccountName=test;AccountKey=dGVzdA==;TableEndpoint=https://test.table.cosmos.azure.com:443/",
        )
        app_module = load_app()
        record = app_module.build_record(dict(EVENTO, created_at=None), "ev-7")
        entity = app_module.azure_entity(record)
        assert (entity["PartitionKey"], entity["RowKey"]) == ("2", "ev-7")
        assert "created_at" not in entity  # Cosmos não aceita valor nulo


class TestConfiguracao:
    def test_provider_invalido_encerra(self, monkeypatch):
        monkeypatch.setenv("CLOUD_PROVIDER", "aws")
        with pytest.raises(SystemExit):
            load_app()

    def test_gcp_sem_projeto_encerra(self, monkeypatch):
        monkeypatch.delenv("GCP_PROJECT_ID")
        with pytest.raises(SystemExit):
            load_app()
