"""Repository pattern: persistence details of events are hidden behind an interface."""
from __future__ import annotations

from typing import Protocol
import sqlite3

from .models import EventIn, RecurrenceIn, ExceptionIn, utc_str


class EventRepository(Protocol):
    """Persistence operations needed by the event application service."""

    def has_category(self, uid: int, cid: int) -> bool: ...
    def get_event(self, uid: int, eid: int) -> sqlite3.Row | None: ...
    def detail(self, uid: int, eid: int) -> dict | None: ...
    def create_rule(self, value: RecurrenceIn | None) -> int | None: ...
    def insert_event(self, uid: int, value: EventIn, rid: int | None) -> int: ...
    def update_event(self, uid: int, eid: int, fields: dict) -> None: ...
    def delete_event(self, uid: int, eid: int) -> None: ...
    def delete_rule(self, rid: int) -> None: ...
    def delete_exceptions(self, eid: int) -> None: ...
    def replace_reminders(self, eid: int, offsets: list[int]) -> None: ...
    def upsert_exception(self, eid: int, value: ExceptionIn) -> None: ...
    def search_event_ids(self, uid: int, q: str | None, category_id: int | None,
                         status_filter: str | None, limit: int, offset: int) -> list[int]: ...


class SQLiteEventRepository:
    """SQLite implementation. Transactions are owned by the application service."""

    def __init__(self, db: sqlite3.Connection):
        self.db = db

    def has_category(self, uid: int, cid: int) -> bool:
        return self.db.execute(
            "SELECT 1 FROM categories WHERE id=? AND user_id=?", (cid, uid)
        ).fetchone() is not None

    def get_event(self, uid: int, eid: int) -> sqlite3.Row | None:
        return self.db.execute(
            "SELECT * FROM events WHERE id=? AND user_id=?", (eid, uid)
        ).fetchone()

    def detail(self, uid: int, eid: int) -> dict | None:
        row = self.get_event(uid, eid)
        if row is None:
            return None
        event = dict(row)
        event["reminders"] = [dict(x) for x in self.db.execute(
            "SELECT * FROM reminders WHERE event_id=? ORDER BY offset_minutes", (eid,)
        )]
        rid = event["recurrence_rule_id"]
        if rid:
            rule = self.db.execute("SELECT * FROM recurrence_rules WHERE id=?", (rid,)).fetchone()
            rec = dict(rule)
            rec["weekdays"] = [x[0] for x in self.db.execute(
                "SELECT weekday FROM recurrence_weekdays WHERE rule_id=? ORDER BY weekday", (rid,)
            )]
            event["recurrence"] = rec
        else:
            event["recurrence"] = None
        event["exceptions"] = [dict(x) for x in self.db.execute(
            "SELECT * FROM event_exceptions WHERE event_id=? ORDER BY original_start_at", (eid,)
        )]
        return event

    def create_rule(self, value: RecurrenceIn | None) -> int | None:
        if value is None:
            return None
        cur = self.db.execute(
            "INSERT INTO recurrence_rules(frequency,interval_value,until_date,occurrence_count) VALUES(?,?,?,?)",
            (value.frequency, value.interval_value, utc_str(value.until_date), value.occurrence_count),
        )
        rid = cur.lastrowid
        for weekday in value.weekdays:
            self.db.execute("INSERT INTO recurrence_weekdays(rule_id,weekday) VALUES(?,?)", (rid, weekday))
        return rid

    def insert_event(self, uid: int, value: EventIn, rid: int | None) -> int:
        cur = self.db.execute(
            """INSERT INTO events(user_id,title,description,location,start_at,end_at,status,category_id,recurrence_rule_id)
            VALUES(?,?,?,?,?,?,?,?,?)""",
            (uid, value.title, value.description, value.location, utc_str(value.start_at),
             utc_str(value.end_at), value.status, value.category_id, rid),
        )
        return cur.lastrowid

    def update_event(self, uid: int, eid: int, fields: dict) -> None:
        if not fields:
            return
        # Only application-service-approved field names are accepted.
        allowed = {"title", "description", "location", "start_at", "end_at", "status",
                   "category_id", "recurrence_rule_id"}
        if not set(fields) <= allowed:
            raise ValueError("Спроба оновити невідоме поле події")
        sql = "UPDATE events SET " + ", ".join(f"{key}=?" for key in fields) + " WHERE id=? AND user_id=?"
        self.db.execute(sql, (*fields.values(), eid, uid))

    def delete_event(self, uid: int, eid: int) -> None:
        self.db.execute("DELETE FROM events WHERE id=? AND user_id=?", (eid, uid))

    def delete_rule(self, rid: int) -> None:
        self.db.execute("DELETE FROM recurrence_rules WHERE id=?", (rid,))

    def delete_exceptions(self, eid: int) -> None:
        self.db.execute("DELETE FROM event_exceptions WHERE event_id=?", (eid,))

    def replace_reminders(self, eid: int, offsets: list[int]) -> None:
        self.db.execute("DELETE FROM reminders WHERE event_id=?", (eid,))
        for offset in offsets:
            self.db.execute("INSERT INTO reminders(event_id,offset_minutes) VALUES(?,?)", (eid, offset))

    def upsert_exception(self, eid: int, value: ExceptionIn) -> None:
        self.db.execute("""INSERT INTO event_exceptions
            (event_id,original_start_at,exception_type,override_start_at,override_end_at,override_title)
            VALUES(?,?,?,?,?,?) ON CONFLICT(event_id,original_start_at) DO UPDATE SET
            exception_type=excluded.exception_type, override_start_at=excluded.override_start_at,
            override_end_at=excluded.override_end_at, override_title=excluded.override_title""",
            (eid, utc_str(value.original_start_at), value.exception_type,
             utc_str(value.override_start_at), utc_str(value.override_end_at), value.override_title),
        )

    def search_event_ids(self, uid: int, q: str | None, category_id: int | None,
                         status_filter: str | None, limit: int, offset: int) -> list[int]:
        sql = "SELECT id FROM events WHERE user_id=?"
        params: list = [uid]
        if q:
            sql += " AND (title LIKE ? OR COALESCE(description,'') LIKE ? OR COALESCE(location,'') LIKE ?)"
            params.extend([f"%{q}%"] * 3)
        if category_id is not None:
            sql += " AND category_id=?"
            params.append(category_id)
        if status_filter is not None:
            sql += " AND status=?"
            params.append(status_filter)
        sql += " ORDER BY start_at,id LIMIT ? OFFSET ?"
        params.extend([limit, offset])
        return [row[0] for row in self.db.execute(sql, params)]


def event_repository(db: sqlite3.Connection) -> EventRepository:
    """Factory for the concrete adapter, allowing substitution in tests later."""
    return SQLiteEventRepository(db)
