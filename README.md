# Jarvis Project

Workspace com quatro modulos principais:

- `jarvis_backend`: API FastAPI, autenticacao, memoria, STT/TTS e orquestracao do assistente.
- `jarvis_agent_windows`: agente local Windows para automacao desktop e wake word.
- `jarvis_flutter`: app Flutter para login, chat, voz e configuracao.
- `jarvis_agent_pi`: agente base para Raspberry Pi ligado ao core por WebSocket.

Estado funcional atual:

- o chat pode usar `Ollama` ou `OpenAI`, escolhido por conta nas configuracoes da app
- a chave OpenAI deixou de ser configurada no Flutter; o backend deve usar `OPENAI_API_KEY`
- quando o Home Assistant esta desligado, a navegacao da app esconde os menus correspondentes

Documentacao de continuidade:

- `MANUAL_DE_CONTINUIDADE.md`: manual tecnico completo com arquitetura, estrutura e notas de continuidade.
- `PLANO_REFACTOR_ARQUITETURA.md`: proposta de evolucao para core central + agentes residentes + consola de gestao.

## Pre-requisitos

- Python 3.11 ou superior
- Flutter SDK instalado
- Chave OpenAI para STT/TTS, visao e opcionalmente chat OpenAI
- Ollama disponivel apenas se quiseres usar o provedor local de chat
- Windows para correr o `jarvis_agent_windows`
- SMTP configurado no backend se quiseres verificacao por email e recuperacao de palavra-passe

## Ordem de arranque

1. Levantar o backend
2. Levantar o agente Windows e/ou o agente Raspberry Pi
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
- `JARVIS_OPENAI_CHAT_MODEL`
- `JARVIS_APP_NAME`
- `JARVIS_SMTP_HOST`
- `JARVIS_SMTP_PORT`
- `JARVIS_SMTP_USERNAME`
- `JARVIS_SMTP_PASSWORD`
- `JARVIS_SMTP_FROM_EMAIL`
- `JARVIS_SMTP_FROM_NAME`
- `JARVIS_SMTP_USE_TLS`

Exemplo SMTP para Gmail:

```env
JARVIS_APP_NAME=Jarvis
JARVIS_SMTP_HOST=smtp.gmail.com
JARVIS_SMTP_PORT=587
JARVIS_SMTP_USERNAME=teu-email@gmail.com
JARVIS_SMTP_PASSWORD=app-password-do-google
JARVIS_SMTP_FROM_EMAIL=teu-email@gmail.com
JARVIS_SMTP_FROM_NAME=Jarvis
JARVIS_SMTP_USE_TLS=true
```

Health check:

```text
GET http://127.0.0.1:8000/health
```

O `GET /health` devolve agora tambem:

- `auth_enabled`
- `user_count`
- `email_enabled`

## Agente Windows

```powershell
cd C:\Work\jarvis_project\jarvis_agent_windows
pip install -r requirements.txt
uvicorn agent:app --host 0.0.0.0 --port 5001
```

Variaveis uteis:

- `JARVIS_CORE_WS_URL=ws://IP_DO_PC:8000/agents/ws`
- `JARVIS_API_TOKEN=change-me`
- `JARVIS_DEVICE_ID=pc-escritorio`
- `JARVIS_DEVICE_NAME=PC Escritorio`

## Agente Raspberry Pi

```powershell
cd C:\Work\jarvis_project\jarvis_agent_pi
pip install -r requirements.txt
uvicorn agent:app --host 0.0.0.0 --port 5002
```

Variaveis uteis:

- `JARVIS_CORE_WS_URL=ws://IP_DO_PC:8000/agents/ws`
- `JARVIS_API_TOKEN=change-me`
- `JARVIS_DEVICE_ID=pi-sala`
- `JARVIS_DEVICE_NAME=Raspberry Pi Sala`

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
  --dart-define=JARVIS_AGENT_BASE_URL=http://IP_DO_PC:5001
```

Notas:

- `127.0.0.1` so funciona se a app estiver na mesma maquina do servico.
- Em telemovel real, usa o IP do PC na rede local.
- O Flutter usa agora login por utilizador e guarda a sessao localmente.
- `JARVIS_API_TOKEN` continua a ser util para compatibilidade e para autenticacao dos agentes, mas a app ja nao depende dele para login normal.
- A escolha entre `Ollama` e `OpenAI` e feita em `Configuracoes > LLM`.
- O modelo OpenAI e escolhido por lista fixa na app; a chave deve existir no backend em `OPENAI_API_KEY`.
- Se o Home Assistant estiver desligado, a app esconde a secao de dispositivos Home Assistant no menu lateral.

## Login e conta

Fluxo atual da app:

1. Criar conta
2. Receber codigo por email
3. Confirmar email
4. Entrar

Tambem tens:

- `Reenviar codigo`
- `Esqueci-me da palavra-passe`
- `Terminar sessao` no menu lateral e nas configuracoes

## Testes

Backend:

```powershell
cd C:\Work\jarvis_project\jarvis_backend
python -B -m unittest discover -s tests -v
```
