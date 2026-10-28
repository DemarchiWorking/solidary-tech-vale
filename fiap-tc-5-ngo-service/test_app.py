import json
from unittest.mock import patch, MagicMock

import pytest


@pytest.fixture(autouse=True)
def mock_env(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql://test:test@localhost/test")


def create_app():
    """Cria uma instância do app com o pool de conexões mockado."""
    with patch("psycopg2.pool.SimpleConnectionPool"):
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
            assert data["service"] == "ngo-service"


class TestCreateNgo:
    def test_create_ngo_missing_fields(self):
        flask_app, _ = create_app()
        with flask_app.test_client() as client:
            response = client.post("/ngos", json={"name": "Sem os outros campos"})
            assert response.status_code == 400

    def test_create_ngo_success(self):
        flask_app, app_module = create_app()
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchone.return_value = {
            "id": 1,
            "name": "Anjos de Patas",
            "email": "contato@anjosdepatas.org",
            "cause": "Proteção Animal",
            "city": "Osasco",
        }
        mock_conn.cursor.return_value.__enter__.return_value = mock_cursor
        app_module.pool.getconn = MagicMock(return_value=mock_conn)
        app_module.pool.putconn = MagicMock()

        with flask_app.test_client() as client:
            response = client.post(
                "/ngos",
                json={
                    "name": "Anjos de Patas",
                    "email": "contato@anjosdepatas.org",
                    "cause": "Proteção Animal",
                    "city": "Osasco",
                },
            )
            assert response.status_code == 201


class TestGetNgos:
    def test_get_ngos_success(self):
        flask_app, app_module = create_app()
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchall.return_value = []
        mock_conn.cursor.return_value.__enter__.return_value = mock_cursor
        app_module.pool.getconn = MagicMock(return_value=mock_conn)
        app_module.pool.putconn = MagicMock()

        with flask_app.test_client() as client:
            response = client.get("/ngos")
            assert response.status_code == 200
            assert json.loads(response.data) == []
