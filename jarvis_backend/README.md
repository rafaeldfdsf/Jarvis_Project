# jarvis_backend

Backend FastAPI do Jarvis. ExpÃµe sessoes de chat, memoria, transcricao, TTS e o fluxo de voz completo.

## Requisitos

- Python 3.11+
- Ollama acessivel no URL configurado
- `OPENAI_API_KEY` para STT/TTS

## Configuracao

```powershell
cd C:\Work\jarvis_project\jarvis_backend
Copy-Item .env.example .env
pip install -r requirements.txt
```

Variaveis mais importantes:

- `OPENAI_API_KEY`: obrigatoria para transcricao, TTS e analise visual do ecra
- `JARVIS_API_TOKEN`: ativa auth Bearer nas rotas da API
- `JARVIS_OLLAMA_URL`: URL do Ollama
- `JARVIS_OLLAMA_MODEL`: modelo usado pelo assistente
- `JARVIS_LLM_TIMEOUT_SECONDS`: timeout das chamadas ao modelo

## Arranque

Modo API:

```powershell
python main.py --mode server --host 0.0.0.0 --port 8000
```

Modo voz local:

```powershell
python main.py --mode voice
```

## Endpoints principais

- `GET /health`
- `POST /sessions`
- `POST /chat`
- `GET /settings`
- `PUT /settings`
- `GET /devices`
- `PUT /devices/{device_id}`
- `GET /memory`
- `POST /transcribe`
- `POST /voice/turn`
- `POST /tts`
- `WS /agents/ws`

Com `JARVIS_API_TOKEN` definido, todas as rotas acima exigem `Authorization: Bearer <token>`, exceto `GET /health`.

## Nova arquitetura de agentes

O backend passou a expor um gateway WebSocket em `WS /agents/ws` para agentes residentes.

Esses agentes:

- registam `device_id`, nome e capacidades;
- aparecem na API `/devices`;
- podem receber comandos do core para executar acoes desktop;
- deixam a app Flutter como consola de configuracao, e nao como coordenadora obrigatoria da wake word.

## Testes

```powershell
python -B -m unittest discover -s tests -v
```
