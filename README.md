# Расписание КОГПК

Android-приложение для просмотра расписания, расписания преподавателей и
электронного журнала колледжа (КОГПК). Данные берутся из кэша
Telegram-бота расписания через тонкий read-only API.

## Возможности

- 📅 **Расписание группы** — текущая и следующая неделя, выделение «сегодня», выбор группы с поиском
- 👨‍🏫 **Преподаватели** — поиск преподавателя и его расписание
- 📒 **Электронный журнал** — оценки и посещаемость по номеру зачётки, средний балл
- 🔄 **Самообновление** — проверка новых версий через GitHub Releases
- 🛠 **Скрытая админ-панель** — 10 тапов по версии в разделе «Ещё» → пароль → статус апдейтеров и ручной перезапуск обновления кэша

## Архитектура

```
kogpk.beget.tech → schedule-bot (парсер, кэш JSON) → schedule_api (FastAPI) → приложение
```

- **Backend** (`server/api.py`): FastAPI, read-only слой над кэшем бота
  (`/root/schedule_bot/cache`). Запускается как `schedule_api.service` на
  `127.0.0.1:8092`, наружу проксируется nginx по пути `https://vpn-ornux.space/sapi/`.
- **App** (`lib/`): Flutter (Android). Базовый URL API — `Api.base` в `lib/api.dart`.

## Сборка

```bash
flutter pub get
flutter build apk --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`.

## Релиз

In-app апдейтер дёргает `releases/latest` репозитория
`yanikto-boop/KOGPK_Schedule` (см. `lib/services/update_service.dart`).
Новый релиз должен быть помечен `--latest` и содержать `.apk`-ассет, а версия
в `pubspec.yaml` — подниматься (и semver, и build-код).

```bash
gh release create vX.Y.Z --repo yanikto-boop/KOGPK_Schedule --latest \
  --notes "..." "build/app/outputs/flutter-apk/app-release.apk#KOGPK_Schedule_X.Y.Z.apk"
```
