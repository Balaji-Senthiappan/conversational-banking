@echo off
rem Serves the mock in a browser at http://localhost:8085
cd /d "%~dp0"
flutter run -d web-server --release --web-port 8085 --web-hostname localhost
