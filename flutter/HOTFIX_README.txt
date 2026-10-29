Виправлення компіляції v1.1 (15.10.2026)

Виправлено 5 помилок, які показала команда flutter run:
1) Колізія класу Category із Flutter foundation annotations
2) Два неіснуючі параметри Container(minHeight: ...)
3) Звернення до nullable EventException.overrideTitle
4) Неправильний аргумент showTimePicker(time: ...)

Застосування у PowerShell:
  Expand-Archive -LiteralPath "$HOME\Downloads\EventReminder_Hotfix_v1_1.zip" -DestinationPath "$HOME\develop\event_reminder_complete" -Force
  cd "$HOME\develop\event_reminder_complete"
  flutter analyze
  flutter test
  flutter run -d 469fc43b

ЗВЕРНИ УВАГУ: Архів хотфіксу потрібно розпаковувати У ПАПКУ ПРОЄКТУ
(event_reminder_complete), а не в develop. Усе дерево папок lib всередині нього.

Збірку Android/Flutter тут запустити не вдалося, тому результат запуску
на твоєму ПК ще потрібно перевірити. Якщо будуть помилки — надішли
повний фрагмент з Error: або FAILURE:.
