import json
from unittest.mock import patch, MagicMock

import pytest


@pytest.fixture(autouse=True)
def mock_env(monkeypatch):
    monkeypatch.setenv("AZURE_SERVICEBUS_CONNECTION_STRING", "Endpoint=sb://test/;SharedAccessKeyName=x;SharedAccessKey=y")
    monkeypatch.setenv("AZURE_SERVICEBUS_QUEUE_NAME", "donation-events")
    monkeypatch.setenv(
        "AZURE_COSMOSDB_CONNECTION_STRING",
        "DefaultEndpointsProtocol=https;AccountName=test;AccountKey=dGVzdA==;TableEndpoint=https://test.table.cosmos.azure.com:443/",
    )
    monkeypatch.setenv("AZURE_COSMOSDB_TABLE_NAME", "DonationNotifications")


def create_app():
    """Cria uma instância do app com o worker (thread + clientes Azure)
    mockado, pra não tentar conectar de verdade durante os testes."""
    with patch("app.start_worker"):
        import importlib
        import app as app_module
        importlib.reload(app_module)
        app_module.app.config["TESTING"] = True
        return app_module.app, app_module


class TestHealth:
    def test_health_returns_ok(self):
        flask_app, _ = create_app()
        with flask_app.test_client() as client:
            response = client.get("/health")
            assert response.status_code == 200
            data = json.loads(response.data)
            assert data["status"] == "ok"
            assert data["service"] == "notification-service"


class TestProcessMessage:
    @patch("app.start_worker")
    def test_process_valid_message(self, _mock_worker):
        import importlib
        import app as app_module
        importlib.reload(app_module)

        mock_table_client = MagicMock()
        message_body = json.dumps({
            "id": 1,
            "ngo_id": 2,
            "amount": 50.0,
            "donor_name": "Fulano",
            "status": "APPROVED",
            "created_at": "2026-09-10T00:00:00Z",
        })
        mock_msg = MagicMock()
        mock_msg.__str__ = MagicMock(return_value=message_body)
        mock_msg.application_properties = {}

        app_module.process_message(mock_table_client, mock_msg)

        mock_table_client.create_entity.assert_called_once()
        entity = mock_table_client.create_entity.call_args.kwargs["entity"]
        assert entity["PartitionKey"] == "2"
        assert entity["donation_id"] == 1
        assert entity["amount"] == 50.0

    @patch("app.start_worker")
    def test_process_invalid_json(self, _mock_worker):
        import importlib
        import app as app_module
        importlib.reload(app_module)

        mock_table_client = MagicMock()
        mock_msg = MagicMock()
        mock_msg.__str__ = MagicMock(return_value="not-json")
        mock_msg.application_properties = {}

        # Não deve levantar exceção — erro é logado e a métrica registrada.
        app_module.process_message(mock_table_client, mock_msg)
        mock_table_client.create_entity.assert_not_called()
