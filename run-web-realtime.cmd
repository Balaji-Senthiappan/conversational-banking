@echo off
rem Serves the mock at http://localhost:8085 with live realtime voice.
rem Start the token service first: python tools\token_service\token_server.py
cd /d "%~dp0"
flutter run -d web-server --release --web-port 8085 --web-hostname localhost --dart-define=REALTIME_TOKEN_URL=http://localhost:8091
