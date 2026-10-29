# Flutter ↔ FastAPI

- The offline app is **unchanged by default**: simply `flutter run -d <device>`.
- Enable remote mode with `--dart-define=EVENT_REMINDER_API_URL=http://127.0.0.1:8000`.
- On a physical Android device connected through USB, first run `adb reverse tcp:8000 tcp:8000`.
- See `../README.md` for detailed Windows / Android Studio instructions.
- The remote client is in `lib/network/` and logs in / registers via email and password.
- This mode uses a server-owned, user-isolated SQLite DB, not the previous Android DB.
- Do not put real passwords into command-line arguments. HTTP localhost/ADB reverse is for the lab debug build only.
