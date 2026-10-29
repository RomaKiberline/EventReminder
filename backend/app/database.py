"""SQLite connection, schema and per-request lifetime. All SQL uses parameters."""
from __future__ import annotations
import os
import sqlite3
from pathlib import Path
from collections.abc import Iterator


def db_path() -> Path:
    return Path(os.getenv("EVENT_REMINDER_DB_PATH", "data/event_reminder_api.sqlite")).resolve()


def connect() -> sqlite3.Connection:
    path = db_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(str(path), timeout=15, check_same_thread=False)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    con.execute("PRAGMA busy_timeout = 5000")
    return con


DDL = """
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY, email TEXT NOT NULL UNIQUE COLLATE NOCASE,
  password_hash TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);
CREATE TABLE IF NOT EXISTS categories (
  id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL,
  name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 60),
  color_hex TEXT NOT NULL CHECK(length(color_hex)=7 AND substr(color_hex,1,1)='#'),
  UNIQUE(user_id, name),
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS recurrence_rules (
  id INTEGER PRIMARY KEY,
  frequency TEXT NOT NULL CHECK(frequency IN ('DAILY','WEEKLY','MONTHLY')),
  interval_value INTEGER NOT NULL DEFAULT 1 CHECK(interval_value>=1),
  until_date TEXT, occurrence_count INTEGER CHECK(occurrence_count>0),
  CHECK(until_date IS NULL OR occurrence_count IS NULL)
);
CREATE TABLE IF NOT EXISTS recurrence_weekdays (
  rule_id INTEGER NOT NULL, weekday INTEGER NOT NULL CHECK(weekday BETWEEN 1 AND 7),
  PRIMARY KEY(rule_id,weekday),
  FOREIGN KEY(rule_id) REFERENCES recurrence_rules(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL,
  title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 150),
  description TEXT, location TEXT, start_at TEXT NOT NULL, end_at TEXT,
  status TEXT NOT NULL DEFAULT 'PLANNED' CHECK(status IN ('PLANNED','DONE','MISSED')),
  category_id INTEGER, recurrence_rule_id INTEGER UNIQUE,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
  CHECK(end_at IS NULL OR end_at>=start_at),
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY(category_id) REFERENCES categories(id) ON DELETE SET NULL,
  FOREIGN KEY(recurrence_rule_id) REFERENCES recurrence_rules(id) ON DELETE RESTRICT
);
CREATE TABLE IF NOT EXISTS reminders (
  id INTEGER PRIMARY KEY, event_id INTEGER NOT NULL,
  offset_minutes INTEGER NOT NULL CHECK(offset_minutes>=0),
  is_enabled INTEGER NOT NULL DEFAULT 1 CHECK(is_enabled IN (0,1)),
  snoozed_until TEXT, UNIQUE(event_id,offset_minutes),
  FOREIGN KEY(event_id) REFERENCES events(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS event_exceptions (
  event_id INTEGER NOT NULL, original_start_at TEXT NOT NULL,
  exception_type TEXT NOT NULL CHECK(exception_type IN ('MODIFIED','CANCELLED','DONE','MISSED')),
  override_start_at TEXT, override_end_at TEXT, override_title TEXT,
  PRIMARY KEY(event_id,original_start_at),
  CHECK(override_end_at IS NULL OR (override_start_at IS NOT NULL AND override_end_at>=override_start_at)),
  CHECK(exception_type='MODIFIED' OR (override_start_at IS NULL AND override_end_at IS NULL AND override_title IS NULL)),
  FOREIGN KEY(event_id) REFERENCES events(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS app_settings (
  user_id INTEGER NOT NULL, setting_key TEXT NOT NULL,
  setting_value TEXT NOT NULL, PRIMARY KEY(user_id,setting_key),
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_events_user_start ON events(user_id,start_at);
CREATE INDEX IF NOT EXISTS idx_events_user_cat ON events(user_id,category_id,start_at);
CREATE INDEX IF NOT EXISTS idx_reminders_event ON reminders(event_id);
CREATE INDEX IF NOT EXISTS idx_event_exceptions_type ON event_exceptions(exception_type);
"""


def init_db() -> None:
    con = connect()
    try:
        con.executescript(DDL)
        con.commit()
    finally:
        con.close()


def get_db() -> Iterator[sqlite3.Connection]:
    con = connect()
    try:
        yield con
    finally:
        con.close()
