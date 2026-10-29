"""Business operations: validation, user ownership, transactions and CRUD."""
from __future__ import annotations
from datetime import datetime
import sqlite3
from fastapi import HTTPException
from .models import EventIn, EventPatch, RecurrenceIn, ExceptionIn, utc_str


def row_dict(row: sqlite3.Row) -> dict:
    return dict(row)


def owned_category(db: sqlite3.Connection, uid: int, cid: int | None) -> None:
    if cid is not None and not db.execute("SELECT 1 FROM categories WHERE id=? AND user_id=?", (cid, uid)).fetchone():
        raise HTTPException(400, "Категорія не існує або належить іншому користувачеві")


def owned_event(db: sqlite3.Connection, uid: int, eid: int) -> sqlite3.Row:
    row = db.execute("SELECT * FROM events WHERE id=? AND user_id=?", (eid, uid)).fetchone()
    if row is None:
        raise HTTPException(404, "Подію не знайдено")
    return row


def event_dict(db: sqlite3.Connection, uid: int, eid: int) -> dict:
    event = row_dict(owned_event(db, uid, eid))
    event["reminders"] = [row_dict(x) for x in db.execute(
        "SELECT * FROM reminders WHERE event_id=? ORDER BY offset_minutes", (eid,)
    )]
    rid = event["recurrence_rule_id"]
    if rid:
        rule = db.execute("SELECT * FROM recurrence_rules WHERE id=?", (rid,)).fetchone()
        rec = row_dict(rule)
        rec["weekdays"] = [x[0] for x in db.execute(
            "SELECT weekday FROM recurrence_weekdays WHERE rule_id=? ORDER BY weekday", (rid,)
        )]
        event["recurrence"] = rec
    else:
        event["recurrence"] = None
    event["exceptions"] = [row_dict(x) for x in db.execute(
        "SELECT * FROM event_exceptions WHERE event_id=? ORDER BY original_start_at", (eid,)
    )]
    return event


def create_rule(db: sqlite3.Connection, value: RecurrenceIn | None) -> int | None:
    if value is None:
        return None
    cur = db.execute(
        "INSERT INTO recurrence_rules(frequency,interval_value,until_date,occurrence_count) VALUES(?,?,?,?)",
        (value.frequency, value.interval_value, utc_str(value.until_date), value.occurrence_count),
    )
    rid = cur.lastrowid
    for weekday in value.weekdays:
        db.execute("INSERT INTO recurrence_weekdays(rule_id,weekday) VALUES(?,?)", (rid, weekday))
    return rid


def create_event(db: sqlite3.Connection, uid: int, value: EventIn) -> dict:
    owned_category(db, uid, value.category_id)
    with db:
        rid = create_rule(db, value.recurrence)
        cur = db.execute(
            """INSERT INTO events(user_id,title,description,location,start_at,end_at,status,category_id,recurrence_rule_id)
            VALUES(?,?,?,?,?,?,?,?,?)""",
            (uid, value.title, value.description, value.location, utc_str(value.start_at),
             utc_str(value.end_at), value.status, value.category_id, rid),
        )
        eid = cur.lastrowid
        for offset in value.reminder_offsets:
            db.execute("INSERT INTO reminders(event_id,offset_minutes) VALUES(?,?)", (eid, offset))
    return event_dict(db, uid, eid)


def edit_event(db: sqlite3.Connection, uid: int, eid: int, patch: EventPatch) -> dict:
    row = owned_event(db, uid, eid)
    changes = patch.model_dump(exclude_unset=True)
    if not changes:
        return event_dict(db, uid, eid)
    if "title" in changes and changes["title"] is None:
        raise HTTPException(422, "Назва не може бути null")
    if "start_at" in changes and changes["start_at"] is None:
        raise HTTPException(422, "Початок не може бути null")
    if "status" in changes and changes["status"] is None:
        raise HTTPException(422, "Статус не може бути null")
    if "category_id" in changes:
        owned_category(db, uid, changes["category_id"])
    start = changes.get("start_at", row["start_at"])
    end = changes.get("end_at", row["end_at"])
    # Both values are normalized UTC strings before comparison.
    start = utc_str(start) if isinstance(start, datetime) else start
    end = utc_str(end) if isinstance(end, datetime) else end
    if end is not None and end < start:
        raise HTTPException(422, "Завершення не може бути раніше початку")
    columns = ("title", "description", "location", "start_at", "end_at", "status", "category_id")
    update = {k: v for k, v in changes.items() if k in columns}
    if "start_at" in update:
        update["start_at"] = start
    if "end_at" in update:
        update["end_at"] = end
    with db:
        if "recurrence" in changes:
            old_rid = row["recurrence_rule_id"]
            rid = create_rule(db, patch.recurrence)
            update["recurrence_rule_id"] = rid
            # Unlink before removing old rule due to ON DELETE RESTRICT.
        if update:
            sql = "UPDATE events SET " + ", ".join(f"{key}=?" for key in update) + " WHERE id=? AND user_id=?"
            db.execute(sql, (*update.values(), eid, uid))
        if "recurrence" in changes and old_rid:
            db.execute("DELETE FROM recurrence_rules WHERE id=?", (old_rid,))
        if "recurrence" in changes and patch.recurrence is None:
            db.execute("DELETE FROM event_exceptions WHERE event_id=?", (eid,))
        if "reminder_offsets" in changes:
            db.execute("DELETE FROM reminders WHERE event_id=?", (eid,))
            for offset in patch.reminder_offsets or []:
                db.execute("INSERT INTO reminders(event_id,offset_minutes) VALUES(?,?)", (eid, offset))
    return event_dict(db, uid, eid)


def delete_event(db: sqlite3.Connection, uid: int, eid: int) -> None:
    row = owned_event(db, uid, eid)
    with db:
        db.execute("DELETE FROM events WHERE id=? AND user_id=?", (eid, uid))
        if row["recurrence_rule_id"]:
            db.execute("DELETE FROM recurrence_rules WHERE id=?", (row["recurrence_rule_id"],))


def upsert_exception(db: sqlite3.Connection, uid: int, eid: int, value: ExceptionIn) -> dict:
    owned_event(db, uid, eid)
    with db:
        db.execute("""INSERT INTO event_exceptions
        (event_id,original_start_at,exception_type,override_start_at,override_end_at,override_title)
        VALUES(?,?,?,?,?,?) ON CONFLICT(event_id,original_start_at) DO UPDATE SET
        exception_type=excluded.exception_type, override_start_at=excluded.override_start_at,
        override_end_at=excluded.override_end_at, override_title=excluded.override_title""",
        (eid, utc_str(value.original_start_at), value.exception_type,
         utc_str(value.override_start_at), utc_str(value.override_end_at), value.override_title),
        )
    return event_dict(db, uid, eid)
