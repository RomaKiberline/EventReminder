"""Лабораторна №11 — 10 модульних тестів EventReminder."""
import pytest
from pydantic import ValidationError

from app.auth import check_password, hash_password
from app.models import EventIn, RecurrenceIn, RegisterIn, utc_str
from datetime import datetime, timezone, timedelta


def test_register_email_normalization():
    value = RegisterIn(email="  USER@Example.COM  ", password="StrongPass123")
    assert value.email == "user@example.com"


def test_register_invalid_email():
    with pytest.raises(ValidationError):
        RegisterIn(email="invalid-email", password="StrongPass123")


def test_register_short_password():
    with pytest.raises(ValidationError):
        RegisterIn(email="user@example.com", password="123")


def test_event_title_trim():
    event = EventIn(title="  Похід у гори  ", start_at="2026-11-02T10:00:00Z")
    assert event.title == "Похід у гори"


def test_event_empty_title():
    with pytest.raises(ValidationError):
        EventIn(title="   ", start_at="2026-11-02T10:00:00Z")


def test_event_end_before_start():
    with pytest.raises(ValidationError):
        EventIn(
            title="Прогулянка",
            start_at="2026-11-02T12:00:00Z",
            end_at="2026-11-02T11:00:00Z",
        )


def test_event_requires_timezone():
    with pytest.raises(ValidationError):
        EventIn(title="Прогулянка", start_at="2026-11-02T12:00:00")


def test_duplicate_reminders_rejected():
    with pytest.raises(ValidationError):
        EventIn(
            title="Тренування",
            start_at="2026-11-02T12:00:00Z",
            reminder_offsets=[15, 15],
        )


def test_invalid_recurrence_weekdays():
    with pytest.raises(ValidationError):
        RecurrenceIn(frequency="WEEKLY", weekdays=[1, 1])


def test_password_hash_validation():
    encoded = hash_password("SafePassword123!")
    assert check_password("SafePassword123!", encoded) is True
    assert check_password("WrongPassword", encoded) is False
    assert "SafePassword123!" not in encoded
