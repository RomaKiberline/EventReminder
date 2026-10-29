-- Лабораторна робота №5: база даних мобільного застосунку подій і нагадувань
-- СУБД: SQLite 3. Дати й час зберігаються в ISO 8601, UTC (суфікс Z).
-- Для повторюваних подій events.start_at задає перше входження серії;
-- наступні входження обчислює прикладна логіка на основі recurrence_rules.
PRAGMA foreign_keys = ON;
BEGIN TRANSACTION;

DROP TABLE IF EXISTS event_exceptions;
DROP TABLE IF EXISTS reminders;
DROP TABLE IF EXISTS events;
DROP TABLE IF EXISTS recurrence_weekdays;
DROP TABLE IF EXISTS recurrence_rules;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS app_settings;

CREATE TABLE categories (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE COLLATE NOCASE
        CHECK (length(trim(name)) BETWEEN 1 AND 60),
    color_hex TEXT NOT NULL
        CHECK (length(color_hex) = 7 AND substr(color_hex, 1, 1) = '#')
);

CREATE TABLE recurrence_rules (
    id INTEGER PRIMARY KEY,
    frequency TEXT NOT NULL
        CHECK (frequency IN ('DAILY', 'WEEKLY', 'MONTHLY')),
    interval_value INTEGER NOT NULL DEFAULT 1 CHECK (interval_value >= 1),
    until_date TEXT,
    occurrence_count INTEGER CHECK (occurrence_count > 0),
    CHECK (until_date IS NULL OR occurrence_count IS NULL)
);

CREATE TABLE recurrence_weekdays (
    rule_id INTEGER NOT NULL,
    weekday INTEGER NOT NULL CHECK (weekday BETWEEN 1 AND 7),
    PRIMARY KEY (rule_id, weekday),
    FOREIGN KEY (rule_id) REFERENCES recurrence_rules(id) ON DELETE CASCADE
);

CREATE TABLE events (
    id INTEGER PRIMARY KEY,
    title TEXT NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 150),
    description TEXT,
    location TEXT,
    start_at TEXT NOT NULL,
    end_at TEXT,
    status TEXT NOT NULL DEFAULT 'PLANNED'
        CHECK (status IN ('PLANNED', 'DONE', 'MISSED')),
    category_id INTEGER,
    recurrence_rule_id INTEGER UNIQUE,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    CHECK (end_at IS NULL OR end_at >= start_at),
    FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
    FOREIGN KEY (recurrence_rule_id) REFERENCES recurrence_rules(id)
        ON DELETE RESTRICT
);

CREATE TABLE reminders (
    id INTEGER PRIMARY KEY,
    event_id INTEGER NOT NULL,
    offset_minutes INTEGER NOT NULL CHECK (offset_minutes >= 0),
    is_enabled INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0, 1)),
    snoozed_until TEXT,
    UNIQUE (event_id, offset_minutes),
    FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE
);

CREATE TABLE event_exceptions (
    event_id INTEGER NOT NULL,
    original_start_at TEXT NOT NULL,
    exception_type TEXT NOT NULL
        CHECK (exception_type IN ('MODIFIED', 'CANCELLED', 'DONE', 'MISSED')),
    override_start_at TEXT,
    override_end_at TEXT,
    override_title TEXT,
    PRIMARY KEY (event_id, original_start_at),
    CHECK (override_end_at IS NULL OR
           (override_start_at IS NOT NULL AND override_end_at >= override_start_at)),
    CHECK (exception_type = 'MODIFIED' OR
           (override_start_at IS NULL AND override_end_at IS NULL AND override_title IS NULL)),
    FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE
);

CREATE TABLE app_settings (
    setting_key TEXT PRIMARY KEY,
    setting_value TEXT NOT NULL
);

CREATE INDEX idx_events_start ON events(start_at);
CREATE INDEX idx_events_category_start ON events(category_id, start_at);
CREATE INDEX idx_reminders_event ON reminders(event_id);
CREATE INDEX idx_event_exceptions_type ON event_exceptions(exception_type);

INSERT INTO categories (id, name, color_hex) VALUES
(1, 'Навчання', '#2878C8'),
(2, 'Робота', '#DB8745'),
(3, 'Особисте', '#7956B3'),
(4, 'Здоров’я', '#31967B');

INSERT INTO recurrence_rules (id, frequency, interval_value, until_date, occurrence_count) VALUES
(1, 'WEEKLY', 1, '2026-11-30', NULL),
(2, 'DAILY', 1, NULL, 5);

INSERT INTO recurrence_weekdays (rule_id, weekday) VALUES
(1, 1), (1, 3);

INSERT INTO events
 (id, title, description, location, start_at, end_at, status, category_id, recurrence_rule_id)
VALUES
(1, 'Лабораторна №5', 'Проєктування бази даних застосунку', 'Університет', '2026-10-16T13:00:00Z', '2026-10-16T14:30:00Z', 'PLANNED', 1, NULL),
(2, 'Командна зустріч', 'Синхронізація із командою', 'Онлайн', '2026-10-19T09:00:00Z', '2026-10-19T10:00:00Z', 'PLANNED', 2, 1),
(3, 'Тренування', 'Коротке тренування', 'Спортзал', '2026-10-16T18:00:00Z', '2026-10-16T19:00:00Z', 'PLANNED', 4, 2),
(4, 'Купити продукти', 'Покупки на вихідні', 'Магазин', '2026-10-17T16:00:00Z', '2026-10-17T16:30:00Z', 'PLANNED', 3, NULL),
(5, 'Здати лабораторну №4', 'Попередня лабораторна робота', 'Університет', '2026-10-14T15:00:00Z', '2026-10-14T16:00:00Z', 'DONE', 1, NULL),
(6, 'Планування тижня', 'Перегляд завдань наступного тижня', 'Дім', '2026-10-18T10:00:00Z', '2026-10-18T10:30:00Z', 'PLANNED', 3, NULL);

INSERT INTO reminders (id, event_id, offset_minutes, is_enabled) VALUES
(1, 1, 60, 1), (2, 1, 15, 1), (3, 2, 30, 1),
(4, 3, 10, 1), (5, 4, 60, 1), (6, 6, 15, 1);

-- Винятки для конкретного входження повторюваної події.
INSERT INTO event_exceptions
(event_id, original_start_at, exception_type, override_start_at, override_end_at, override_title)
VALUES
(2, '2026-10-21T09:00:00Z', 'MODIFIED', '2026-10-21T11:00:00Z', '2026-10-21T12:00:00Z', NULL),
(2, '2026-10-26T09:00:00Z', 'CANCELLED', NULL, NULL, NULL),
(3, '2026-10-17T18:00:00Z', 'DONE', NULL, NULL, NULL);

INSERT INTO app_settings (setting_key, setting_value) VALUES
('theme', 'system'),
('default_reminder_minutes', '15');

COMMIT;
