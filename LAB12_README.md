# Лабораторна робота №12 — EventReminder

Тема: Вдосконалення наявної архітектури проєкту шляхом рефакторингу та впровадження дизайн-патернів.

## Чому саме ці патерни?

1. **Repository (архітектурний патерн)**. У початковому `backend/app/services.py` бізнес-правила, транзакції та SQL були в одному модулі. Тепер SQL для CRUD подій, нагадувань, повторень, винятків та пошуку знаходиться в `app/repositories.py`. Контракт `EventRepository` (Protocol) описує потрібні операції, `SQLiteEventRepository` реалізує їх для SQLite. Це дозволяє тестувати бізнес-логіку окремо й замінити БД без переписування сервісів.

2. **Observer (поведінковий GoF-патерн)**. Після створення/редагування/видалення події кілька незалежних підсистем можуть реагувати на зміну. Раніше такого механізму не було. `app/observers.py` містить `EventPublisher`, інтерфейс `EventObserver` та двох підписників: `SqliteAuditObserver` (збереження історії в таблицю `event_audit`) і `LoggingObserver` (логи без особистого тексту події). Подія публікується **після коміту основної транзакції**; збій спостерігача не повертає помилку клієнту після успішного CRUD.

## Структура змін

```text
backend/
  app/
    repositories.py          # НОВИЙ: Repository, SQLiteEventRepository
    observers.py             # НОВИЙ: Observer, Publisher, два обробники
    services.py              # ЗМІНЕНО: сервіс делегує SQL репозиторію, публікує події
    database.py              # ЗМІНЕНО: таблиця event_audit (CREATE IF NOT EXISTS)
    main.py                  # ЗМІНЕНО: пошук через Repository; маршрути незмінні
  tests/
    test_lab12_patterns.py    # НОВИЙ: 4 тести патернів
```

## UML / архітектура до змін

```mermaid
flowchart LR
  R[FastAPI routes / main.py] --> S[services.py: бізнес-правила + SQL]
  S --> DB[(SQLite: events, reminders)]
```

## UML / архітектура після змін

```mermaid
classDiagram
  class EventRepository {
    <<Protocol>>
    +get_event(uid, eid)
    +insert_event(uid, value, rid)
    +update_event(uid, eid, fields)
    +search_event_ids(...)
  }
  class SQLiteEventRepository {
    -db
  }
  class EventPublisher {
    -observers
    +subscribe(observer)
    +notify(change, db)
  }
  class EventObserver {
    <<Protocol>>
    +update(change, db)
  }
  class SqliteAuditObserver
  class LoggingObserver
  SQLiteEventRepository ..|> EventRepository
  EventPublisher o-- EventObserver
  SqliteAuditObserver ..|> EventObserver
  LoggingObserver ..|> EventObserver
```

Потік: `main.py -> services.py -> EventRepository -> SQLite`; після успішного коміту: `services.py -> EventPublisher -> AuditObserver / LoggingObserver`.
