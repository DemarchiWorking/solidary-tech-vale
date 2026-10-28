import json
from unittest.mock import patch, MagicMock

import pytest


@pytest.fixture(autouse=True)
def mock_env(monkeypatch):
    monkeypatch.setenv("CLOUD_PROVIDER", "aws")
    monkeypatch.setenv("AWS_REGION", "us-east-1")
    monkeypatch.setenv("AWS_DYNAMODB_TABLE", "TestVolunteers")


def create_app():
    """Cria uma instância do app com o boto3.resource mockado (evita
    credenciais/conexão real com AWS durante os testes)."""
    with patch("boto3.resource"):
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
            assert data["service"] == "volunteer-service"


class TestRegisterVolunteer:
    def test_missing_fields(self):
        flask_app, _ = create_app()
        with flask_app.test_client() as client:
            response = client.post("/volunteers", json={"name": "Fulano"})
            assert response.status_code == 400

    def test_register_success(self):
        flask_app, app_module = create_app()
        app_module.put_volunteer = MagicMock()

        with flask_app.test_client() as client:
            response = client.post(
                "/volunteers",
                json={"name": "Fulano", "email": "fulano@example.com", "ngo_id": 1},
            )
            assert response.status_code == 201
            data = json.loads(response.data)
            assert data["name"] == "Fulano"
            assert data["ngo_id"] == 1
            app_module.put_volunteer.assert_called_once()


class TestGetVolunteers:
    def test_get_volunteers_success(self):
        flask_app, app_module = create_app()
        app_module.get_volunteers_by_ngo = MagicMock(return_value=[])

        with flask_app.test_client() as client:
            response = client.get("/volunteers/1")
            assert response.status_code == 200
            assert json.loads(response.data) == []
