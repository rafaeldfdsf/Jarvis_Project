# jarvis_backend

Backend FastAPI do Jarvis. Expoe autenticacao, sessoes de chat, memoria, transcricao, TTS, configuracoes e o fluxo de voz completo.

## Requisitos

- Python 3.11+
- Ollama acessivel no URL configurado
- `OPENAI_API_KEY` para STT/TTS
- SMTP configurado se quiseres verificacao por email e recuperacao de palavra-passe

## Configuracao

```powershell
cd C:\Work\jarvis_project\jarvis_backend
Copy-Item .env.example .env
pip install -r requirements.txt
```

Variaveis mais importantes:

- `OPENAI_API_KEY`: obrigatoria para transcricao, TTS e analise visual do ecra
- `JARVIS_API_TOKEN`: ativa auth Bearer de compatibilidade e autenticacao dos agentes
- `JARVIS_OLLAMA_URL`: URL do Ollama
- `JARVIS_OLLAMA_MODEL`: modelo usado pelo assistente
- `JARVIS_LLM_TIMEOUT_SECONDS`: timeout das chamadas ao modelo
- `JARVIS_APP_NAME`: nome usado nos emails transacionais
- `JARVIS_SMTP_HOST`: servidor SMTP
- `JARVIS_SMTP_PORT`: porta SMTP
- `JARVIS_SMTP_USERNAME`: utilizador SMTP
- `JARVIS_SMTP_PASSWORD`: password SMTP ou app password
- `JARVIS_SMTP_FROM_EMAIL`: email remetente
- `JARVIS_SMTP_FROM_NAME`: nome remetente
- `JARVIS_SMTP_USE_TLS`: ativa `starttls`

Exemplo Gmail:

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
- `POST /auth/register`
- `POST /auth/verify-email`
- `POST /auth/resend-verification`
- `POST /auth/login`
- `POST /auth/forgot-password`
- `POST /auth/reset-password`
- `GET /auth/me`
- `POST /auth/logout`
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

## Autenticacao atual

Fluxo principal:

1. `POST /auth/register`
2. envio de codigo por email
3. `POST /auth/verify-email`
4. `POST /auth/login`

Recuperacao:

1. `POST /auth/forgot-password`
2. envio de codigo por email
3. `POST /auth/reset-password`

Notas:

- contas nao verificadas nao conseguem entrar
- quando a password e reposta, as sessoes antigas dessa conta sao invalidadas
- `GET /health` mostra `auth_enabled`, `user_count` e `email_enabled`
- o Flutter usa sessoes de utilizador por defeito, sem depender de `JARVIS_API_TOKEN`

## Nova arquitetura de agentes

O backend expoe um gateway WebSocket em `WS /agents/ws` para agentes residentes.

Esses agentes:

- registam `device_id`, nome e capacidades
- aparecem na API `/devices`
- podem receber comandos do core para executar acoes desktop
- deixam a app Flutter como consola de configuracao, e nao como coordenadora obrigatoria da wake word

## Testes

```powershell
python -B -m unittest discover -s tests -v
```
