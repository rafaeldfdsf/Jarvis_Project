# jarvis_agent_pi

Agente base para Raspberry Pi ligado ao `jarvis_core` por WebSocket.

## Objetivo

Este agente foi preparado para:

- registar o Raspberry Pi no core;
- anunciar capacidades locais;
- servir de base para wake word, captura de audio e TTS local;
- receber comandos futuros do core sem depender da app Flutter aberta.

## Arranque

```powershell
cd C:\Work\jarvis_project\jarvis_agent_pi
pip install -r requirements.txt
uvicorn agent:app --host 0.0.0.0 --port 5002
```

Variaveis uteis:

- `JARVIS_DEVICE_ID`
- `JARVIS_DEVICE_NAME`
- `JARVIS_DEVICE_LOCATION`
- `JARVIS_CORE_WS_URL`
- `JARVIS_API_TOKEN`

## Estado atual

O agente ja:

- se liga ao core;
- aparece em `/devices`;
- expoe `/health`;
- suporta ativacao e paragem logica da wake word.

A parte especifica de audio local no Raspberry Pi continua modular para ser afinada na maquina fisica.
