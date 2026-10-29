-- Запускати після Lab5_SQLite.sql; всі часові значення - UTC.
PRAGMA foreign_keys = ON;

-- Тест 1. Майбутні базові записи календаря (повторення розгортає логіка застосунку).
SELECT e.id, e.title, e.start_at, c.name AS category
FROM events e LEFT JOIN categories c ON c.id = e.category_id
WHERE e.start_at >= '2026-10-15T00:00:00Z' AND e.status = 'PLANNED'
ORDER BY e.start_at LIMIT 10;

-- Тест 2. Кількість подій за категоріями.
SELECT c.name AS category, COUNT(e.id) AS event_count
FROM categories c LEFT JOIN events e ON e.category_id = c.id
GROUP BY c.id, c.name ORDER BY c.id;

-- Тест 3. Година нагадування для ПЕРШОГО входження події.
-- Для інших входжень повторюваної події час обчислює застосунок.
SELECT e.title, r.offset_minutes,
       datetime(e.start_at, '-' || r.offset_minutes || ' minutes') AS fire_at_utc
FROM reminders r JOIN events e ON e.id = r.event_id
WHERE r.is_enabled = 1 ORDER BY fire_at_utc, e.id;

-- Тест 4. Вибірка подій у категорії «Навчання».
SELECT e.id, e.title, e.status
FROM events e JOIN categories c ON c.id = e.category_id
WHERE c.name = 'Навчання' ORDER BY e.start_at;

-- Тест 5. Правила повторення та обрані дні тижня.
SELECT e.title, rr.frequency, rr.interval_value,
       COALESCE(GROUP_CONCAT(rw.weekday), 'усі дні') AS weekdays,
       rr.until_date, rr.occurrence_count
FROM events e
JOIN recurrence_rules rr ON rr.id = e.recurrence_rule_id
LEFT JOIN recurrence_weekdays rw ON rw.rule_id = rr.id
GROUP BY e.id ORDER BY e.id;

-- Тест 6. Винятки повторів.
SELECT e.title, ex.original_start_at, ex.exception_type, ex.override_start_at
FROM event_exceptions ex JOIN events e ON e.id = ex.event_id
ORDER BY ex.event_id, ex.original_start_at;

-- Тест 7. Контроль цілісності БД (очікується: ok; foreign_key_check - порожній результат).
PRAGMA integrity_check;
PRAGMA foreign_key_check;

-- Тест 8. Перевірка каскадного видалення в транзакції з ROLLBACK
-- (не змінює початкові демонстраційні дані).
BEGIN;
INSERT INTO events(id, title, start_at, status)
VALUES (999, 'Тимчасовий запис', '2026-10-30T10:00:00Z', 'PLANNED');
INSERT INTO reminders(id, event_id, offset_minutes)
VALUES (999, 999, 15);
DELETE FROM events WHERE id = 999;
SELECT COUNT(*) AS reminders_after_delete
FROM reminders WHERE event_id = 999;
ROLLBACK;
