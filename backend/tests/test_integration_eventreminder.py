"""Лабораторна робота №11: 3 інтеграційні тести FastAPI + SQLite."""
import sqlite3

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture
def api_and_database(tmp_path, monkeypatch):
    """Створює окрему тимчасову SQLite БД для кожного тесту."""
    database_path = tmp_path / "lab11_integration.sqlite"
    monkeypatch.setenv("EVENT_REMINDER_DB_PATH", str(database_path))
    monkeypatch.setenv(
        "EVENT_REMINDER_SECRET_KEY",
        "lab11-test-only-secret-key-with-more-than-32-characters",
    )
    with TestClient(app) as client:
        yield client, database_path


def create_user_and_authorize(client, email="integration@example.com"):
    """Реєструє тестового користувача та повертає заголовок JWT."""
    credentials = {"email": email, "password": "IntegrationPass123!"}
    result = client.post("/api/auth/register", json=credentials)
    assert result.status_code == 201, result.text
    result = client.post("/api/auth/login", json=credentials)
    assert result.status_code == 200, result.text
    return {"Authorization": f"Bearer {result.json()['access_token']}"}


def test_it_001_registration_saves_user_and_defaults(api_and_database):
    """IT-001: API реєстрації створює користувача, категорії та налаштування в БД."""
    client, database_path = api_and_database
    create_user_and_authorize(client)

    with sqlite3.connect(database_path) as db:
        user = db.execute(
            "SELECT id, email, password_hash FROM users WHERE email = ?",
            ("integration@example.com",),
        ).fetchone()
        assert user is not None
        assert user[1] == "integration@example.com"
        assert user[2] != "IntegrationPass123!"  # Пароль не зберігається відкритим текстом
        assert db.execute(
            "SELECT COUNT(*) FROM categories WHERE user_id = ?", (user[0],)
        ).fetchone()[0] == 4
        assert db.execute(
            "SELECT setting_value FROM app_settings WHERE user_id = ? AND setting_key = 'theme'",
            (user[0],),
        ).fetchone()[0] == "system"


def test_it_002_api_create_and_edit_are_persisted(api_and_database):
    """IT-002: POST і PATCH події зберігають правильні дані в SQLite."""
    client, database_path = api_and_database
    headers = create_user_and_authorize(client)
    result = client.post(
        "/api/events",
        headers=headers,
        json={
            "title": "Похід у гори",
            "start_at": "2026-11-02T09:00:00Z",
            "end_at": "2026-11-02T17:00:00Z",
            "reminder_offsets": [30, 60],
        },
    )
    assert result.status_code == 201, result.text
    event_id = result.json()["id"]

    edited = client.patch(
        f"/api/events/{event_id}",
        headers=headers,
        json={"title": "Похід у Карпати", "status": "DONE"},
    )
    assert edited.status_code == 200, edited.text

    with sqlite3.connect(database_path) as db:
        row = db.execute(
            "SELECT title, status, start_at FROM events WHERE id = ?", (event_id,)
        ).fetchone()
        assert row == ("Похід у Карпати", "DONE", "2026-11-02T09:00:00Z")
        offsets = db.execute(
            "SELECT offset_minutes FROM reminders WHERE event_id = ? ORDER BY offset_minutes",
            (event_id,),
        ).fetchall()
        assert [item[0] for item in offsets] == [30, 60]

    fetched = client.get(f"/api/events/{event_id}", headers=headers)
    assert fetched.status_code == 200
    assert fetched.json()["title"] == "Похід у Карпати"


def test_it_003_delete_cascades_to_related_records(api_and_database):
    """IT-003: DELETE видаляє подію, нагадування та її винятки з SQLite."""
    client, database_path = api_and_database
    headers = create_user_and_authorize(client)
    created = client.post(
        "/api/events",
        headers=headers,
        json={
            "title": "Тренування",
            "start_at": "2026-11-02T10:00:00Z",
            "reminder_offsets": [15],
            "recurrence": {"frequency": "DAILY", "interval_value": 1},
        },
    )
    assert created.status_code == 201, created.text
    event_id = created.json()["id"]
    rule_id = created.json()["recurrence_rule_id"]

    exception = client.put(
        f"/api/events/{event_id}/exceptions",
        headers=headers,
        json={
            "original_start_at": "2026-11-03T10:00:00Z",
            "exception_type": "CANCELLED",
        },
    )
    assert exception.status_code == 200, exception.text
    deleted = client.delete(f"/api/events/{event_id}", headers=headers)
    assert deleted.status_code == 204, deleted.text

    with sqlite3.connect(database_path) as db:
        for table in ("events", "reminders", "event_exceptions"):
            column = "id" if table == "events" else "event_id"
            count = db.execute(
                f"SELECT COUNT(*) FROM {table} WHERE {column} = ?", (event_id,)
            ).fetchone()[0]
            assert count == 0, f"У таблиці {table} залишилися пов'язані дані"
        assert db.execute(
            "SELECT COUNT(*) FROM recurrence_rules WHERE id = ?", (rule_id,)
        ).fetchone()[0] == 0

    assert client.get(f"/api/events/{event_id}", headers=headers).status_code == 404
