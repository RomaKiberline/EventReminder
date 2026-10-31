"""HTTP controllers: authentication, categories, events, exceptions, search."""
from contextlib import asynccontextmanager
from pydantic import BaseModel
from typing import Literal
from datetime import datetime
import sqlite3
from fastapi import Depends, FastAPI, HTTPException, Query, status
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from .auth import hash_password, check_password, token_for, current_user, signing_key
from .database import get_db, init_db
from .models import RegisterIn, LoginIn, CategoryIn, EventIn, EventPatch, ExceptionIn, utc_str, validate_aware
from .services import owned_category, owned_event, event_dict, create_event, edit_event, delete_event, upsert_exception
from .repositories import event_repository


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    signing_key()
    yield


app = FastAPI(
    title="Event Reminder REST API", version="1.0.0",
    description="Лабораторні №8–10: FastAPI + SQLite + JWT + CRUD + валідація.",
    lifespan=lifespan,
)


@app.exception_handler(RequestValidationError)
async def validation_handler(request, exc):
    # Do not echo user passwords in error output.
    safe = [{"loc": list(err["loc"]), "msg": err["msg"], "type": err["type"]} for err in exc.errors()]
    return JSONResponse(status_code=422, content={"detail": safe})


@app.get("/api/health", tags=["Health"])
def health():
    return {"status": "ok", "service": "event-reminder-api"}


PRESETS = (
    ("Навчання", "#2878C8"), ("Робота", "#DB8745"),
    ("Особисте", "#7956B3"), ("Здоров’я", "#31967B"),
)


@app.post("/api/auth/register", status_code=201, tags=["Authentication"])
def register(value: RegisterIn, db: sqlite3.Connection = Depends(get_db)):
    try:
        with db:
            cur = db.execute("INSERT INTO users(email,password_hash) VALUES(?,?)",
                             (value.email, hash_password(value.password)))
            uid = cur.lastrowid
            db.executemany("INSERT INTO categories(user_id,name,color_hex) VALUES(?,?,?)",
                           [(uid, name, color) for name, color in PRESETS])
            db.execute("INSERT INTO app_settings(user_id,setting_key,setting_value) VALUES(?,?,?)",
                       (uid, "theme", "system"))
    except sqlite3.IntegrityError:
        raise HTTPException(409, "Email уже зареєстрований") from None
    return {"id": uid, "email": value.email}


@app.post("/api/auth/login", tags=["Authentication"])
def login(value: LoginIn, db: sqlite3.Connection = Depends(get_db)):
    row = db.execute("SELECT id,password_hash FROM users WHERE email=? COLLATE NOCASE",
                     (value.email.strip(),)).fetchone()
    if not row or not check_password(value.password, row["password_hash"]):
        raise HTTPException(401, "Неправильний email або пароль")
    return {"access_token": token_for(row["id"]), "token_type": "bearer"}


@app.get("/api/auth/me", tags=["Authentication"])
def me(uid: int = Depends(current_user), db: sqlite3.Connection = Depends(get_db)):
    row = db.execute("SELECT id,email,created_at FROM users WHERE id=?", (uid,)).fetchone()
    return dict(row)


@app.get("/api/categories", tags=["Categories"])
def list_categories(uid: int = Depends(current_user), db: sqlite3.Connection = Depends(get_db)):
    return [dict(row) for row in db.execute(
        "SELECT id,name,color_hex FROM categories WHERE user_id=? ORDER BY name COLLATE NOCASE", (uid,)
    )]


@app.post("/api/categories", status_code=201, tags=["Categories"])
def add_category(value: CategoryIn, uid: int = Depends(current_user), db: sqlite3.Connection = Depends(get_db)):
    try:
        with db:
            cur = db.execute("INSERT INTO categories(user_id,name,color_hex) VALUES(?,?,?)",
                             (uid, value.name, value.color_hex))
    except sqlite3.IntegrityError:
        raise HTTPException(409, "Категорія з такою назвою вже існує") from None
    return {"id": cur.lastrowid, **value.model_dump()}


@app.put("/api/categories/{cid}", tags=["Categories"])
def update_category(cid: int, value: CategoryIn, uid: int = Depends(current_user), db: sqlite3.Connection = Depends(get_db)):
    owned_category(db, uid, cid)
    try:
        with db:
            db.execute("UPDATE categories SET name=?,color_hex=? WHERE id=? AND user_id=?",
                       (value.name, value.color_hex, cid, uid))
    except sqlite3.IntegrityError:
        raise HTTPException(409, "Категорія з такою назвою вже існує") from None
    return {"id": cid, **value.model_dump()}


@app.delete("/api/categories/{cid}", status_code=204, tags=["Categories"])
def remove_category(cid: int, uid: int = Depends(current_user), db: sqlite3.Connection = Depends(get_db)):
    owned_category(db, uid, cid)
    with db:
        db.execute("DELETE FROM categories WHERE id=? AND user_id=?", (cid, uid))


@app.get("/api/events", tags=["Events"])
def list_events(
    q: str | None = Query(default=None, max_length=100),
    category_id: int | None = None,
    status_filter: Literal["PLANNED", "DONE", "MISSED"] | None = Query(default=None, alias="status"),
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    uid: int = Depends(current_user), db: sqlite3.Connection = Depends(get_db),
):
    ids = event_repository(db).search_event_ids(uid, q, category_id, status_filter, limit, offset)
    return [event_dict(db, uid, eid) for eid in ids]


@app.post("/api/events", status_code=201, tags=["Events"])
def add_event(value: EventIn, uid: int = Depends(current_user), db: sqlite3.Connection = Depends(get_db)):
    return create_event(db, uid, value)


@app.get("/api/events/{eid}", tags=["Events"])
def get_event(eid: int, uid: int = Depends(current_user), db: sqlite3.Connection = Depends(get_db)):
    return event_dict(db, uid, eid)


@app.patch("/api/events/{eid}", tags=["Events"])
def patch_event(eid: int, value: EventPatch, uid: int = Depends(current_user), db: sqlite3.Connection = Depends(get_db)):
    return edit_event(db, uid, eid, value)


@app.delete("/api/events/{eid}", status_code=204, tags=["Events"])
def remove_event(eid: int, uid: int = Depends(current_user), db: sqlite3.Connection = Depends(get_db)):
    delete_event(db, uid, eid)


@app.put("/api/events/{eid}/exceptions", tags=["Events"])
def set_exception(eid: int, value: ExceptionIn, uid: int = Depends(current_user), db: sqlite3.Connection = Depends(get_db)):
    return upsert_exception(db, uid, eid, value)


class SettingIn(BaseModel):
    value: Literal["system", "light", "dark"]


@app.get("/api/settings", tags=["Settings"])
def list_settings(uid: int = Depends(current_user), db: sqlite3.Connection = Depends(get_db)):
    return {row["setting_key"]: row["setting_value"] for row in db.execute(
        "SELECT setting_key,setting_value FROM app_settings WHERE user_id=?", (uid,)
    )}


@app.put("/api/settings/theme", tags=["Settings"])
def set_theme(value: SettingIn, uid: int = Depends(current_user), db: sqlite3.Connection = Depends(get_db)):
    with db:
        db.execute("""INSERT INTO app_settings(user_id,setting_key,setting_value)
        VALUES(?, 'theme', ?) ON CONFLICT(user_id,setting_key)
        DO UPDATE SET setting_value=excluded.setting_value""", (uid, value.value))
    return {"theme": value.value}


@app.delete("/api/events/{eid}/exceptions", status_code=204, tags=["Events"])
def clear_exception(
    eid: int, original_start_at: datetime = Query(...),
    uid: int = Depends(current_user), db: sqlite3.Connection = Depends(get_db),
):
    owned_event(db, uid, eid)
    try:
        normalized = utc_str(validate_aware(original_start_at))
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from None
    with db:
        result = db.execute("""DELETE FROM event_exceptions
        WHERE event_id=? AND original_start_at=?""", (eid, normalized))
    if not result.rowcount:
        raise HTTPException(404, "Виняток події не знайдено")
