# games_server

Игровой сервер приложения и сайта: ники, таблицы лидеров (Block Boom, дурак),
дурак онлайн по WebSocket. Живёт на том же хосте, что бот расписания:

- код: `/root/games_server/` (копия здесь), окружение `venv/` (fastapi, uvicorn[standard])
- сервис: `games_server.service` → `127.0.0.1:8093`, наружу `/gapi/` (nginx в remnawave-nginx)
- база: `/root/games_server/games.db` (SQLite; комнаты и партии — только в памяти)

Тесты (на сервере): `venv/bin/python test_durak.py && venv/bin/python test_server.py`
