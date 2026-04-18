# Jarvis Project

Workspace com tres modulos separados:

- `jarvis_backend`: API FastAPI, orquestracao do assistente, memoria e integracao com LLM/STT/TTS.
- `jarvis_agent_windows`: agente local Windows para automacoes desktop e wake word.
- `jarvis_flutter`: app Flutter para chat e modo voz.

Documentacao de continuidade:

- `MANUAL_DE_CONTINUIDADE.md`: manual tecnico completo com arquitetura, estrutura e explicacao modulo a modulo.

## Pre-requisitos

- Python 3.11 ou superior
- Flutter SDK instalado
- Chave OpenAI para STT/TTS
- Ollama disponivel para o modelo local configurado no backend
- Windows para correr o `jarvis_agent_windows`

## Ordem de arranque

1. Levantar o backend
2. Levantar o agente Windows
3. Arrancar a app Flutter

## Backend

```powershell
cd C:\Work\jarvis_project\jarvis_backend
Copy-Item .env.example .env
pip install -r requirements.txt
python main.py --mode server --host 0.0.0.0 --port 8000
```

Variaveis principais em `.env`:

- `OPENAI_API_KEY`
- `JARVIS_API_TOKEN`
- `JARVIS_OLLAMA_URL`
- `JARVIS_OLLAMA_MODEL`

Health check:

```text
GET http://127.0.0.1:8000/health
```

## Agente Windows

```powershell
cd C:\Work\jarvis_project\jarvis_agent_windows
pip install -r requirements.txt
uvicorn agent:app --host 0.0.0.0 --port 5001
```

Health check:

```text
GET http://127.0.0.1:5001/health
```

## Flutter

```powershell
cd C:\Work\jarvis_project\jarvis_flutter
flutter pub get
flutter run `
  --dart-define=JARVIS_API_BASE_URL=http://IP_DO_PC:8000 `
  --dart-define=JARVIS_AGENT_BASE_URL=http://IP_DO_PC:5001 `
  --dart-define=JARVIS_API_TOKEN=change-me
```

Notas:

- `127.0.0.1` so funciona se a app estiver na mesma maquina do servico.
- Em telemovel real, usa o IP do PC na rede local.
- Se ativares auth no backend, o token do Flutter tem de coincidir com `JARVIS_API_TOKEN` do backend.

## Testes

Backend:

```powershell
cd C:\Work\jarvis_project\jarvis_backend
python -B -m unittest discover -s tests -v
```
