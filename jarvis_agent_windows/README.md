# jarvis_agent_windows

Agente FastAPI para Windows com automacoes desktop, captura de ecra e wake word local.

## Requisitos

- Windows
- Python 3.11+
- Dependencias instaladas a partir de `requirements.txt`

## Instalar e arrancar

```powershell
cd C:\Work\jarvis_project\jarvis_agent_windows
pip install -r requirements.txt
uvicorn agent:app --host 0.0.0.0 --port 5001
```

## Endpoints

- `GET /health`
- `POST /action`
- `GET /screen/capture`
- `POST /wake-word/start`
- `POST /wake-word/stop`
- `GET /wake-word/events/next`

## Acoes principais

- `open_app`
- `open_url`
- `close_app`
- `close_window`
- `close_tab`
- `type_text`
- `press_keys`
- `youtube_search`
- `activate_window`
- `minimize_window`
- `screenshot`

## Notas

- O agente foi desenhado para correr na maquina Windows que controla o desktop.
- A wake word depende de audio local e das dependencias opcionais carregadas em runtime.
- A acao `screenshot` grava `screenshot.png` localmente e esse ficheiro fica ignorado pelo git.
- O endpoint `GET /screen/capture` devolve a captura atual do ecra em base64 para o backend poder analisar o que esta visivel.