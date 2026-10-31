"""Observer pattern: independent reactions to committed event changes."""
from __future__ import annotations

from dataclasses import dataclass
import logging
import sqlite3
from typing import Protocol

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class EventChange:
    user_id: int
    event_id: int
    action: str


class EventObserver(Protocol):
    def update(self, change: EventChange, db: sqlite3.Connection) -> None: ...


class SqliteAuditObserver:
    """Persist event lifecycle history; deleted event IDs remain auditable."""
    def update(self, change: EventChange, db: sqlite3.Connection) -> None:
        with db:
            db.execute(
                "INSERT INTO event_audit(user_id,event_id,action) VALUES(?,?,?)",
                (change.user_id, change.event_id, change.action),
            )


class LoggingObserver:
    """Emit structured, non-sensitive action metadata to application logs."""
    def update(self, change: EventChange, db: sqlite3.Connection) -> None:
        logger.info("event action=%s user_id=%s event_id=%s",
                    change.action, change.user_id, change.event_id)


class EventPublisher:
    """Subscribers are isolated: audit/log failure never masks a committed CRUD result."""
    def __init__(self, observers: list[EventObserver]):
        self._observers = list(observers)

    def subscribe(self, observer: EventObserver) -> None:
        if observer not in self._observers:
            self._observers.append(observer)

    def unsubscribe(self, observer: EventObserver) -> None:
        if observer in self._observers:
            self._observers.remove(observer)

    def notify(self, change: EventChange, db: sqlite3.Connection) -> None:
        for observer in self._observers:
            try:
                observer.update(change, db)
            except Exception:
                logger.exception("Observer failed after committed event change: %s", change.action)


event_publisher = EventPublisher([SqliteAuditObserver(), LoggingObserver()])
