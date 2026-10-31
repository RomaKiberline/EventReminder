"""Лабораторна №12: перевірка Repository та Observer у реальній роботі API."""
import sqlite3

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.observers import EventChange, EventPublisher
from app.repositories import SQLiteEventRepository


@pytest.fixture
def api(tmp_path, monkeypatch):
    db_path = tmp_path / "lab12.sqlite"
    monkeypatch.setenv("EVENT_REMINDER_DB_PATH", str(db_path))
    monkeypatch.setenv("EVENT_REMINDER_SECRET_KEY", "lab12-local-test-only-secret-key-1234567890")
    with TestClient(app) as c:
        yield c, db_path


def login(c, email="lab12@example.com"):
    credentials = {"email": email, "password": "SafePassword123!"}
    r = c.post("/api/auth/register", json=credentials)
    assert r.status_code == 201, r.text
    token = c.post("/api/auth/login", json=credentials)
    assert token.status_code == 200, token.text
    return {"Authorization": "Bearer " + token.json()["access_token"]}


def test_lab12_observer_audit_after_create_update_delete(api):
    """Observer зберігає три незалежні записи й не видаляє історію після DELETE."""
    c, db_path = api
    headers = login(c)
    created = c.post("/api/events", headers=headers, json={
        "title": "Похід у Карпати", "start_at": "2026-11-04T10:00:00Z"
    })
    assert created.status_code == 201
    eid = created.json()["id"]
    uid = created.json()["user_id"]
    changed = c.patch(f"/api/events/{eid}", headers=headers, json={"title": "Похід із друзями"})
    assert changed.status_code == 200
    deleted = c.delete(f"/api/events/{eid}", headers=headers)
    assert deleted.status_code == 204
    assert c.get(f"/api/events/{eid}", headers=headers).status_code == 404

    with sqlite3.connect(db_path) as db:
        audit = db.execute(
            "SELECT user_id,event_id,action FROM event_audit WHERE user_id=? ORDER BY id", (uid,)
        ).fetchall()
        assert audit == [(uid, eid, "CREATED"), (uid, eid, "UPDATED"), (uid, eid, "DELETED")]
        assert db.execute("SELECT COUNT(*) FROM events WHERE id=?", (eid,)).fetchone()[0] == 0


def test_lab12_invalid_event_has_no_observer_entry(api):
    """Помилка валідації не повинна викликати Observer."""
    c, db_path = api
    headers = login(c)
    r = c.post("/api/events", headers=headers, json={
        "title": "   ", "start_at": "2026-11-04T10:00:00Z"
    })
    assert r.status_code == 422
    with sqlite3.connect(db_path) as db:
        assert db.execute("SELECT COUNT(*) FROM event_audit").fetchone()[0] == 0


def test_lab12_repository_user_isolation_and_whitelist(api):
    """Repository не віддає чужі події та не дозволяє довільні SQL-стовпці."""
    c, db_path = api
    user1 = login(c, "first@example.com")
    user2 = login(c, "second@example.com")
    first_id = c.get("/api/auth/me", headers=user1).json()["id"]
    second_id = c.get("/api/auth/me", headers=user2).json()["id"]
    created = c.post("/api/events", headers=user1, json={
        "title": "Приватна подія", "start_at": "2026-11-04T10:00:00Z"
    })
    eid = created.json()["id"]
    with sqlite3.connect(db_path) as db:
        db.row_factory = sqlite3.Row
        repo = SQLiteEventRepository(db)
        assert repo.get_event(first_id, eid)["title"] == "Приватна подія"
        assert repo.get_event(second_id, eid) is None
        with pytest.raises(ValueError):
            repo.update_event(first_id, eid, {"unsafe_column": "bad"})
    assert c.get(f"/api/events/{eid}", headers=user2).status_code == 404


def test_lab12_observer_error_does_not_hide_success(caplog):
    """Падіння одного підписника не блокує інших (подія вже закомічена)."""
    seen = []

    class Broken:
        def update(self, change, db):
            raise RuntimeError("Тестовий збій")

    class Collector:
        def update(self, change, db):
            seen.append(change.action)

    publisher = EventPublisher([Broken(), Collector()])
    with sqlite3.connect(":memory:") as db:
        publisher.notify(EventChange(1, 5, "CREATED"), db)
    assert seen == ["CREATED"]
    assert "Observer failed" in caplog.text
