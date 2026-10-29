# Event Reminder API — лабораторні №8–10

**Предметна область:** мобільний застосунок для особистих подій і нагадувань.  
**Backend:** Python + FastAPI + SQLite + JWT.  
**Frontend:** Flutter Android/Windows у сусідній папці `../flutter/`. Є робочий HTTP-клієнт із JWT (вмикається прапорцем `EVENT_REMINDER_API_URL`; див. кореневий README).

## 1. Запуск на Windows 11 (PowerShell)

Відкрий папку `EventReminder_Backend_Lab8-10` у VS Code / PyCharm або PowerShell.

```powershell
cd "C:\Users\kiber\develop\EventReminder_Backend_Lab8-10"
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

**Важливо:** `cd` — приклад. Якщо розпакував ZIP в іншу папку, зміни шлях. Якщо команда `py` не працює, скористайся `python`.

API документація: **http://127.0.0.1:8000/docs**.  
Перевірка сервера: http://127.0.0.1:8000/api/health.  
Файл SQLite створюється автоматично за шляхом `data/event_reminder_api.sqlite`.

Зупинка сервера — `Ctrl+C`.

## 2. Демонстрація Swagger UI для звіту

1. Відкрий http://127.0.0.1:8000/docs.
2. Розкрий `POST /api/auth/register`, натисни **Try it out** і введи:

   ```json
   {"email":"student@example.com","password":"DemoPassword2026!"}
   ```

   Натисни **Execute**. Має бути **201** (створено). Повторна реєстрація того ж email дає **409**.
3. Розкрий `POST /api/auth/login`, введи той самий email і пароль. Відповідь **200** містить `access_token`.
4. Натисни **Authorize** (значок замка), встав лише значення `access_token` і підтвердь. У Swagger UI, якщо форма має окреме поле для префікса, дотримуйся її підказки; зазвичай для HTTP Bearer вводиться сам токен.
5. Тепер виконай `GET /api/categories` — після реєстрації є чотири стандартні категорії.
6. Виконай `POST /api/events` з прикладом:

   ```json
   {
     "title": "Лабораторна №8–10",
     "description": "Перевірка REST API",
     "start_at": "2026-11-02T11:00:00Z",
     "end_at": "2026-11-02T12:00:00Z",
     "status": "PLANNED",
     "reminder_offsets": [15, 60],
     "recurrence": {"frequency":"WEEKLY", "interval_value":1, "weekdays":[1,3]}
   }
   ```

   Відповідь **201** містить ID події, два нагадування й правило повторення.
7. Виконай `GET /api/events` → **200** зі списком.
8. Скопіюй `id` і виконай `PATCH /api/events/{eid}` зі вмістом `{"status":"DONE"}` → **200**.
9. Валідація: `POST /api/events` з `{"title":"", "start_at":"2026-11-02T11:00:00Z"}` → **422**.
10. За потреби виконай `DELETE /api/events/{eid}` → **204**, потім `GET` для того самого ID → **404**.

## 3. Перевірка автоматичними тестами

В **іншому** терміналі у папці проєкту:

```powershell
.\.venv\Scripts\python.exe -m pytest -v
```

5 тестів працюють з **окремою тимчасовою** SQLite БД. У випробуваннях є автентифікація, авторизація, ізоляція даних, CRUD, повторення, винятки, валідація й видалення.

## 4. API (основні маршрути)

| Метод | Шлях | Функція | Доступ |
|---|---|---|---|
| GET | `/api/health` | Стан сервера | Відкритий |
| POST | `/api/auth/register` | Реєстрація | Відкритий |
| POST | `/api/auth/login` | JWT-токен | Відкритий |
| GET | `/api/auth/me` | Поточний користувач | JWT |
| GET/POST | `/api/categories` | Перелік / нова категорія | JWT |
| PUT/DELETE | `/api/categories/{cid}` | Зміна / видалення категорії | JWT |
| GET/POST | `/api/events` | Пошук / створення події | JWT |
| GET/PATCH/DELETE | `/api/events/{eid}` | Перегляд / зміна / видалення | JWT |
| PUT | `/api/events/{eid}/exceptions` | Виняток повторюваної події | JWT |

Пошук: `/api/events?q=текст&status=PLANNED&limit=20&offset=0`.

Використані HTTP-коди: **200, 201, 204, 400, 401, 404, 409, 422**.

## 5. Структура проєкту

```text
EventReminder_Backend_Lab8-10/
├── app/
│   ├── main.py          # HTTP-контролери, REST API, Swagger
│   ├── models.py        # Pydantic, серверна валідація
│   ├── auth.py          # JWT, PBKDF2, авторизація
│   ├── services.py      # Бізнес-логіка, транзакції, CRUD
│   └── database.py      # SQLite, DDL, підключення
├── tests/test_api.py    # Автоматичні API-тести
├── requirements.txt
├── requirements-dev.txt
├── .env.example
└── README.md
```

## 6. Зв'язок із Flutter і попередніми лабораторними

У ZIP є спільний Flutter-застосунок з новим `ApiEventRepository`, HTTP-клієнтом і екраном авторизації. Серверна база має знайомі таблиці `events`, `categories`, `reminders`, `recurrence_rules`, `recurrence_weekdays`, `event_exceptions`, `app_settings`, а також `users` і `user_id`. API для налаштувань: `GET /api/settings`, `PUT /api/settings/theme`; видалення винятку: `DELETE /api/events/{eid}/exceptions?original_start_at=<ISO8601>`.

**Важливо:** це окрема серверна SQLite, не міграція оригінальної бази телефону. Стандартний режим Flutter залишається офлайн. Для запуску на справжньому телефоні через USB див. інструкцію `../README.md` про `adb reverse`.

## 7. Безпека та обмеження

- Паролі зберігаються як PBKDF2-HMAC-SHA256 із випадковою сіллю, а не відкритим текстом.
- JWT підписаний секретом. Якщо змінна `EVENT_REMINDER_SECRET_KEY` не задана, для локальної демонстрації випадковий ключ зберігається у `data/event_reminder_api.secret` (файл не входить до Git). Для розгортання ключ потрібно налаштувати окремо.
- Сервіс за замовчуванням слухає **127.0.0.1**, тобто тільки на цьому комп'ютері. Не публікуй API у відкритий інтернет без HTTPS, належного управління секретами та додаткового захисту.
- Реалізовано ізоляцію даних між зареєстрованими користувачами.
- Не реалізовано обмеження частоти входу, email-підтвердження, скидання пароля, refresh-token та хмарну синхронізацію. Для лабораторного прототипу вони не потрібні, для продуктивного сервісу — важливі.

## 8. Звіт та Git

У звіті необхідно показати: структуру backend, код, реальні скриншоти Swagger (реєстрація, GET/POST/PATCH/DELETE, помилка 422), запуск і результат `pytest -v`, власне Git-посилання.

```powershell
git init
git add .
git commit -m "Lab 8-10: Event Reminder REST API"
```

Після створення GitHub/GitLab репозиторію додай реальне посилання до звіту. Секрети, база та `.venv` ігноруються `.gitignore`.
