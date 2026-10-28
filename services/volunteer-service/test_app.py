import importlib
import json
from unittest.mock import patch, MagicMock

import pytest


@pytest.fixture(autouse=True)
def mock_env(monkeypatch):
    monkeypatch.setenv("CLOUD_PROVIDER", "gcp")
    monkeypatch.setenv("GCP_PROJECT_ID", "solidarytech-test")
    monkeypatch.delenv("FIRESTORE_COLLECTION", raising=False)


def create_app():
    """Recarrega o app com o cliente do Firestore mockado (sem credenciais
    nem conexão durante os testes). Devolve também o mock do cliente."""
    with patch("google.cloud.firestore.Client") as client_cls:
        import app as app_module
        importlib.reload(app_module)
        app_module.app.config["TESTING"] = True
        return app_module.app, app_module, client_cls.return_value


class TestHealth:
    def test_health_returns_ok(self):
        flask_app, _, _ = create_app()
        with flask_app.test_client() as client:
            response = client.get("/health")
            assert response.status_code == 200
            data = json.loads(response.data)
            assert data["status"] == "ok"
            assert data["service"] == "volunteer-service"


class TestRegisterVolunteer:
    def test_missing_fields(self):
        flask_app, _, _ = create_app()
        with flask_app.test_client() as client:
            response = client.post("/volunteers", json={"name": "Fulano"})
            assert response.status_code == 400

    def test_body_nao_json_devolve_400(self):
        flask_app, _, _ = create_app()
        with flask_app.test_client() as client:
            response = client.post("/volunteers", data="texto", content_type="text/plain")
            assert response.status_code == 400

    def test_register_grava_no_firestore_com_volunteer_id(self):
        flask_app, _, db = create_app()
        with flask_app.test_client() as client:
            response = client.post(
                "/volunteers",
                json={"name": "Fulano", "email": "fulano@example.com", "ngo_id": "1"},
            )
        assert response.status_code == 201
        data = json.loads(response.data)
        assert data["name"] == "Fulano"
        assert data["ngo_id"] == 1

        db.collection.assert_called_with("volunteers")
        db.collection.return_value.document.assert_called_with(data["volunteer_id"])
        gravado = db.collection.return_value.document.return_value.set.call_args.args[0]
        assert gravado["email"] == "fulano@example.com"
        assert gravado["ngo_id"] == 1

    def test_falha_do_firestore_devolve_500(self):
        flask_app, _, db = create_app()
        db.collection.return_value.document.return_value.set.side_effect = RuntimeError("indisponível")
        with flask_app.test_client() as client:
            response = client.post(
                "/volunteers",
                json={"name": "Fulano", "email": "fulano@example.com", "ngo_id": 1},
            )
        assert response.status_code == 500


class TestGetVolunteers:
    def test_consulta_por_ngo_id(self):
        flask_app, _, db = create_app()
        doc = MagicMock()
        doc.to_dict.return_value = {"volunteer_id": "v1", "name": "Ana", "email": "a@x", "ngo_id": 3, "registered_at": "1"}
        db.collection.return_value.where.return_value.stream.return_value = [doc]

        with flask_app.test_client() as client:
            response = client.get("/volunteers/3")
        assert response.status_code == 200
        assert json.loads(response.data) == [doc.to_dict.return_value]

        filtro = db.collection.return_value.where.call_args.kwargs["filter"]
        assert (filtro.field_path, filtro.op_string, filtro.value) == ("ngo_id", "==", 3)


class TestSelecaoDeBackend:
    def test_azure_usa_cosmos(self, monkeypatch):
        monkeypatch.setenv("CLOUD_PROVIDER", "azure")
        monkeypatch.setenv(
            "AZURE_COSMOSDB_CONNECTION_STRING",
            "DefaultEndpointsProtocol=https;AccountName=test;AccountKey=dGVzdA==;TableEndpoint=https://test.table.cosmos.azure.com:443/",
        )
        with patch("azure.data.tables.TableServiceClient") as svc:
            import app as app_module
            importlib.reload(app_module)
            table = svc.from_connection_string.return_value.get_table_client.return_value
            app_module.put_volunteer({"volunteer_id": "v1", "name": "A", "email": "a@x", "ngo_id": 5, "registered_at": "1"})
            entity = table.create_entity.call_args.kwargs["entity"]
            assert (entity["PartitionKey"], entity["RowKey"]) == ("5", "v1")

    def test_provider_invalido_encerra(self, monkeypatch):
        monkeypatch.setenv("CLOUD_PROVIDER", "aws")
        import app as app_module
        with pytest.raises(SystemExit):
            importlib.reload(app_module)

    def test_gcp_sem_projeto_encerra(self, monkeypatch):
        monkeypatch.delenv("GCP_PROJECT_ID")
        import app as app_module
        with pytest.raises(SystemExit):
            importlib.reload(app_module)
