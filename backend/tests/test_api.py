"""End-to-end API tests with a disposable real SQLite database."""
import os
import pytest
from fastapi.testclient import TestClient
from app.main import app


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("EVENT_REMINDER_DB_PATH", str(tmp_path / "test.sqlite"))
    monkeypatch.setenv("EVENT_REMINDER_SECRET_KEY", "only-for-test-aaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    with TestClient(app) as test_client:
        yield test_client


def register_and_login(c, email="student@example.com"):
    r = c.post("/api/auth/register", json={"email": email, "password": "SuperSafePassword42!"})
    assert r.status_code == 201, r.text
    token = c.post("/api/auth/login", json={"email": email, "password": "SuperSafePassword42!"})
    assert token.status_code == 200, token.text
    return {"Authorization": "Bearer " + token.json()["access_token"]}


def test_health_auth_and_reject_invalid_password(client):
    c = client
    assert c.get("/api/health").json()["status"] == "ok"
    assert c.get("/api/events").status_code == 401
    h = register_and_login(c)
    assert c.get("/api/auth/me", headers=h).status_code == 200
    assert len(c.get("/api/categories", headers=h).json()) == 4
    assert c.post("/api/auth/login", json={"email":"student@example.com","password":"wrong"}).status_code == 401
    assert c.post("/api/auth/register", json={"email":"student@example.com","password":"SuperSafePassword42!"}).status_code == 409


def test_event_crud_recurrence_reminders_and_exceptions(client):
    c = client
    h = register_and_login(c)
    category = c.get("/api/categories", headers=h).json()[0]["id"]
    payload = {
        "title": "Лабораторна №8–10", "start_at": "2026-11-02T11:00:00Z",
        "end_at": "2026-11-02T12:00:00Z", "category_id": category,
        "reminder_offsets": [15, 60],
        "recurrence": {"frequency":"WEEKLY", "interval_value":1, "weekdays":[1, 3]},
    }
    r = c.post("/api/events", json=payload, headers=h)
    assert r.status_code == 201, r.text
    event = r.json()
    eid = event["id"]
    assert len(event["reminders"]) == 2
    assert event["recurrence"]["weekdays"] == [1,3]
    assert len(c.get("/api/events", headers=h, params={"q":"Лабораторна"}).json()) == 1
    r = c.patch(f"/api/events/{eid}", json={"status":"DONE", "reminder_offsets":[30]}, headers=h)
    assert r.status_code == 200
    assert r.json()["status"] == "DONE"
    assert len(r.json()["reminders"]) == 1
    ex = c.put(f"/api/events/{eid}/exceptions", headers=h, json={
        "original_start_at":"2026-11-04T11:00:00Z", "exception_type":"CANCELLED"
    })
    assert ex.status_code == 200 and len(ex.json()["exceptions"]) == 1
    assert c.delete(f"/api/events/{eid}", headers=h).status_code == 204
    assert c.get(f"/api/events/{eid}", headers=h).status_code == 404


def test_server_validation_and_user_isolation(client):
    c = client
    h1 = register_and_login(c, "user1@example.com")
    h2 = register_and_login(c, "user2@example.com")
    base = {"title":"Тест", "start_at":"2026-11-02T11:00:00Z"}
    r = c.post("/api/events", headers=h1, json=base)
    assert r.status_code == 201, r.text
    eid = r.json()["id"]
    assert c.get(f"/api/events/{eid}", headers=h2).status_code == 404
    assert c.get("/api/events", headers=h2).json() == []
    assert c.delete(f"/api/events/{eid}", headers=h2).status_code == 404
    assert c.post("/api/events", headers=h1, json={"title":"  ","start_at":"2026-11-02T11:00:00Z"}).status_code == 422
    assert c.post("/api/events", headers=h1, json={
        "title":"Час", "start_at":"2026-11-02T11:00:00Z", "end_at":"2026-11-02T10:00:00Z"
    }).status_code == 422
    assert c.post("/api/events", headers=h1, json={**base,"category_id":99999}).status_code == 400
    assert c.patch(f"/api/events/{eid}", headers=h1, json={"title":None}).status_code == 422
    assert c.patch(f"/api/events/{eid}", headers=h1, json={"start_at":"2026-11-01T12:00:00Z"}).status_code == 200


def test_category_crud_and_recurrence_cleanup(client):
    c = client
    h = register_and_login(c)
    r = c.post("/api/categories", headers=h, json={"name":"Хобі","color_hex":"#BB4477"})
    assert r.status_code == 201, r.text
    cid = r.json()["id"]
    assert c.post("/api/categories", headers=h, json={"name":"Хобі","color_hex":"#BB4477"}).status_code == 409
    e = c.post("/api/events", headers=h, json={
        "title":"Малювання", "start_at":"2026-11-01T12:00:00Z", "category_id":cid,
        "recurrence":{"frequency":"DAILY","interval_value":1}
    })
    assert e.status_code == 201, e.text
    eid = e.json()["id"]
    assert c.patch(f"/api/events/{eid}", headers=h, json={"recurrence":None}).status_code == 200
    assert c.delete(f"/api/categories/{cid}", headers=h).status_code == 204
    assert c.get(f"/api/events/{eid}", headers=h).json()["category_id"] is None


def test_settings_and_delete_exception(client):
    c = client
    h = register_and_login(c)
    r = c.get("/api/settings", headers=h)
    assert r.status_code == 200 and r.json()["theme"] == "system"
    assert c.put("/api/settings/theme", json={"value": "dark"}, headers=h).json()["theme"] == "dark"
    assert c.put("/api/settings/theme", json={"value": "invalid"}, headers=h).status_code == 422
    ev = c.post("/api/events", headers=h, json={
        "title": "Тренування", "start_at": "2026-11-02T11:00:00Z",
        "recurrence": {"frequency": "WEEKLY", "weekdays": [1,3]}
    }).json()
    eid = ev["id"]
    args = {"original_start_at": "2026-11-04T11:00:00Z", "exception_type": "DONE"}
    assert c.put(f"/api/events/{eid}/exceptions", headers=h, json=args).status_code == 200
    assert c.delete(f"/api/events/{eid}/exceptions", headers=h,
        params={"original_start_at":"2026-11-04T11:00:00Z"}).status_code == 204
    assert c.get(f"/api/events/{eid}", headers=h).json()["exceptions"] == []
    assert c.put(f"/api/events/{eid}/exceptions", headers=h, json=args).status_code == 200
    assert c.patch(f"/api/events/{eid}", headers=h, json={"recurrence":None}).status_code == 200
    assert c.get(f"/api/events/{eid}", headers=h).json()["exceptions"] == []
