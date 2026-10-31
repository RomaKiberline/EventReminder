"""Business rules and transactions. Persistence is delegated to EventRepository."""
from __future__ import annotations

from datetime import datetime
import sqlite3
from fastapi import HTTPException

from .models import EventIn, EventPatch, ExceptionIn, utc_str
from .repositories import event_repository
from .observers import EventChange, event_publisher


def owned_category(db: sqlite3.Connection, uid: int, cid: int | None) -> None:
    if cid is not None and not event_repository(db).has_category(uid, cid):
        raise HTTPException(400, "Категорія не існує або належить іншому користувачеві")


def owned_event(db: sqlite3.Connection, uid: int, eid: int) -> sqlite3.Row:
    row = event_repository(db).get_event(uid, eid)
    if row is None:
        raise HTTPException(404, "Подію не знайдено")
    return row


def event_dict(db: sqlite3.Connection, uid: int, eid: int) -> dict:
    event = event_repository(db).detail(uid, eid)
    if event is None:
        raise HTTPException(404, "Подію не знайдено")
    return event


def create_event(db: sqlite3.Connection, uid: int, value: EventIn) -> dict:
    owned_category(db, uid, value.category_id)
    repo = event_repository(db)
    with db:
        rid = repo.create_rule(value.recurrence)
        eid = repo.insert_event(uid, value, rid)
        repo.replace_reminders(eid, value.reminder_offsets)
    # Observer events are published only AFTER the main transaction commits.
    event_publisher.notify(EventChange(uid, eid, "CREATED"), db)
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
    repo = event_repository(db)
    with db:
        if "recurrence" in changes:
            old_rid = row["recurrence_rule_id"]
            update["recurrence_rule_id"] = repo.create_rule(patch.recurrence)
        repo.update_event(uid, eid, update)
        if "recurrence" in changes and old_rid:
            repo.delete_rule(old_rid)
        if "recurrence" in changes and patch.recurrence is None:
            repo.delete_exceptions(eid)
        if "reminder_offsets" in changes:
            repo.replace_reminders(eid, patch.reminder_offsets or [])
    event_publisher.notify(EventChange(uid, eid, "UPDATED"), db)
    return event_dict(db, uid, eid)


def delete_event(db: sqlite3.Connection, uid: int, eid: int) -> None:
    row = owned_event(db, uid, eid)
    repo = event_repository(db)
    with db:
        repo.delete_event(uid, eid)
        if row["recurrence_rule_id"]:
            repo.delete_rule(row["recurrence_rule_id"])
    event_publisher.notify(EventChange(uid, eid, "DELETED"), db)


def upsert_exception(db: sqlite3.Connection, uid: int, eid: int, value: ExceptionIn) -> dict:
    owned_event(db, uid, eid)
    with db:
        event_repository(db).upsert_exception(eid, value)
    return event_dict(db, uid, eid)
