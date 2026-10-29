"""Input validation independent of the Flutter UI (server is responsible)."""
from datetime import datetime, timezone
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
import re


def utc_str(d: datetime | None) -> str | None:
    return None if d is None else d.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def validate_aware(d: datetime | None) -> datetime | None:
    if d is not None and (d.tzinfo is None or d.utcoffset() is None):
        raise ValueError("Дата повинна містити часовий пояс (наприклад, Z або +02:00)")
    return d


class RegisterIn(BaseModel):
    email: str = Field(min_length=5, max_length=254)
    password: str = Field(min_length=8, max_length=128)

    @field_validator("email")
    @classmethod
    def email_format(cls, v: str) -> str:
        v = v.strip().lower()
        if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", v):
            raise ValueError("Некоректна електронна адреса")
        return v


class LoginIn(BaseModel):
    email: str
    password: str


class CategoryIn(BaseModel):
    name: str = Field(min_length=1, max_length=60)
    color_hex: str = Field(pattern=r"^#[0-9a-fA-F]{6}$")

    @field_validator("name")
    @classmethod
    def nonempty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Назва категорії не може бути порожньою")
        return v.strip()


class RecurrenceIn(BaseModel):
    frequency: Literal["DAILY", "WEEKLY", "MONTHLY"]
    interval_value: int = Field(default=1, ge=1, le=365)
    until_date: datetime | None = None
    occurrence_count: int | None = Field(default=None, ge=1)
    weekdays: list[int] = Field(default_factory=list)

    @field_validator("until_date")
    @classmethod
    def check_date(cls, v: datetime | None) -> datetime | None:
        return validate_aware(v)

    @field_validator("weekdays")
    @classmethod
    def weekdays_valid(cls, v: list[int]) -> list[int]:
        if any(d < 1 or d > 7 for d in v) or len(set(v)) != len(v):
            raise ValueError("Дні тижня мають бути різними числами від 1 до 7")
        return v

    @model_validator(mode="after")
    def check_until(self):
        if self.until_date and self.occurrence_count:
            raise ValueError("Задай або until_date, або occurrence_count")
        if self.weekdays and self.frequency != "WEEKLY":
            raise ValueError("Список weekdays доступний лише для WEEKLY")
        return self


class EventIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str = Field(min_length=1, max_length=150)
    description: str | None = None
    location: str | None = None
    start_at: datetime
    end_at: datetime | None = None
    status: Literal["PLANNED", "DONE", "MISSED"] = "PLANNED"
    category_id: int | None = Field(default=None, ge=1)
    recurrence: RecurrenceIn | None = None
    reminder_offsets: list[int] = Field(default_factory=list, max_length=20)

    @field_validator("title")
    @classmethod
    def title_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("Назва події не може бути порожньою")
        return v.strip()

    @field_validator("start_at", "end_at")
    @classmethod
    def aware_time(cls, v: datetime | None) -> datetime | None:
        return validate_aware(v)

    @field_validator("reminder_offsets")
    @classmethod
    def offset_valid(cls, v: list[int]) -> list[int]:
        if any(o < 0 or o > 525600 for o in v) or len(set(v)) != len(v):
            raise ValueError("Нагадування повинні бути різними числами від 0 до 525600")
        return v

    @model_validator(mode="after")
    def ends_after_start(self):
        if self.end_at is not None and self.end_at < self.start_at:
            raise ValueError("Час завершення не може бути раніше початку")
        return self


class EventPatch(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str | None = Field(default=None, max_length=150)
    description: str | None = None
    location: str | None = None
    start_at: datetime | None = None
    end_at: datetime | None = None
    status: Literal["PLANNED", "DONE", "MISSED"] | None = None
    category_id: int | None = Field(default=None, ge=1)
    recurrence: RecurrenceIn | None = None
    reminder_offsets: list[int] | None = Field(default=None, max_length=20)

    @field_validator("start_at", "end_at")
    @classmethod
    def aware_time(cls, v: datetime | None) -> datetime | None:
        return validate_aware(v)

    @field_validator("title")
    @classmethod
    def not_blank(cls, v: str | None) -> str | None:
        if v is not None and not v.strip():
            raise ValueError("Назва події не може бути порожньою")
        return v.strip() if v is not None else None

    @field_validator("reminder_offsets")
    @classmethod
    def check_offsets(cls, v: list[int] | None) -> list[int] | None:
        if v is not None and (any(o < 0 or o > 525600 for o in v) or len(set(v)) != len(v)):
            raise ValueError("Некоректні або повторні інтервали нагадувань")
        return v

class ExceptionIn(BaseModel):
    original_start_at: datetime
    exception_type: Literal["MODIFIED", "CANCELLED", "DONE", "MISSED"]
    override_start_at: datetime | None = None
    override_end_at: datetime | None = None
    override_title: str | None = Field(default=None, max_length=150)

    @field_validator("original_start_at", "override_start_at", "override_end_at")
    @classmethod
    def aware_time(cls, v: datetime | None) -> datetime | None:
        return validate_aware(v)

    @model_validator(mode="after")
    def check_overrides(self):
        if self.exception_type != "MODIFIED" and any(
            v is not None for v in (self.override_start_at, self.override_end_at, self.override_title)
        ):
            raise ValueError("Тільки MODIFIED може мати override-поля")
        if self.override_end_at and not self.override_start_at:
            raise ValueError("override_end_at потребує override_start_at")
        if self.override_end_at and self.override_start_at and self.override_end_at < self.override_start_at:
            raise ValueError("Новий кінець не може бути раніше нового початку")
        return self
