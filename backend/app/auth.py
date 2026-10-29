"""JWT authentication, PBKDF2 password hashing, user-scoped access."""
from __future__ import annotations
from datetime import datetime, timedelta, timezone
from pathlib import Path
import base64
import hashlib
import hmac
import os
import secrets
import sqlite3
import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from .database import get_db

bearer = HTTPBearer(auto_error=False)


def signing_key() -> str:
    from .database import db_path
    key = os.getenv("EVENT_REMINDER_SECRET_KEY")
    if key:
        if len(key) < 32:
            raise RuntimeError("EVENT_REMINDER_SECRET_KEY повинен мати 32+ символи")
        return key
    path: Path = db_path().with_suffix(".secret")
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        try:
            with path.open("x", encoding="utf-8") as f:
                f.write(secrets.token_urlsafe(48))
        except FileExistsError:
            pass
    return path.read_text(encoding="utf-8").strip()


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    iterations = 350000
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, iterations)
    return f"pbkdf2_sha256${iterations}${base64.b64encode(salt).decode()}${base64.b64encode(digest).decode()}"


def check_password(password: str, encoded: str) -> bool:
    try:
        method, raw_iterations, raw_salt, raw_digest = encoded.split("$")
        if method != "pbkdf2_sha256":
            return False
        actual = hashlib.pbkdf2_hmac("sha256", password.encode(), base64.b64decode(raw_salt), int(raw_iterations))
        return hmac.compare_digest(actual, base64.b64decode(raw_digest))
    except (ValueError, TypeError):
        return False


def token_for(uid: int) -> str:
    now = datetime.now(timezone.utc)
    return jwt.encode({"sub": str(uid), "iat": now, "exp": now + timedelta(hours=8)}, signing_key(), algorithm="HS256")


def current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: sqlite3.Connection = Depends(get_db),
) -> int:
    error = HTTPException(status_code=401, detail="Потрібен чинний Bearer token", headers={"WWW-Authenticate": "Bearer"})
    if credentials is None:
        raise error
    try:
        payload = jwt.decode(credentials.credentials, signing_key(), algorithms=["HS256"])
        raw_uid = payload.get("sub")
        if not isinstance(raw_uid, str) or not raw_uid.isdecimal():
            raise error
        uid = int(raw_uid)
    except jwt.PyJWTError:
        raise error from None
    if db.execute("SELECT id FROM users WHERE id=?", (uid,)).fetchone() is None:
        raise error
    return uid
