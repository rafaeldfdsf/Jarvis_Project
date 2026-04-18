# jarvis_flutter

Cliente Flutter do Jarvis com chat, voz, memoria e integracao com o agente Windows.

## Requisitos

- Flutter SDK
- Backend em execucao
- Agente Windows em execucao se quiseres a parte de wake word/automacao local

## Instalar dependencias

```powershell
cd C:\Work\jarvis_project\jarvis_flutter
flutter pub get
```

## Arrancar

```powershell
flutter run `
  --dart-define=JARVIS_API_BASE_URL=http://IP_DO_PC:8000 `
  --dart-define=JARVIS_AGENT_BASE_URL=http://IP_DO_PC:5001 `
  --dart-define=JARVIS_API_TOKEN=change-me
```

## Variaveis suportadas

- `JARVIS_API_BASE_URL`: URL base do backend FastAPI
- `JARVIS_AGENT_BASE_URL`: URL base do agente Windows
- `JARVIS_API_TOKEN`: token Bearer usado pelo backend quando a auth esta ativa

## Notas importantes

- `http://127.0.0.1:8000` e `http://127.0.0.1:5001` so funcionam se a app estiver na mesma maquina.
- Em Android/iPhone real, usa o IP do computador na rede local.
- Se o backend tiver auth ativa, o token do Flutter tem de coincidir com `JARVIS_API_TOKEN` definido no backend.

## Comandos uteis

```powershell
flutter test
flutter analyze
```
