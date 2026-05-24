# jarvis_flutter

Cliente Flutter do Jarvis com chat, voz, memoria, configuracoes por conta e integracao com o agente Windows.

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
  --dart-define=JARVIS_AGENT_BASE_URL=http://IP_DO_PC:5001
```

## Variaveis suportadas

- `JARVIS_API_BASE_URL`: URL base do backend FastAPI
- `JARVIS_AGENT_BASE_URL`: URL base do agente Windows
- `JARVIS_API_TOKEN`: opcional para compatibilidade; o fluxo principal usa login por utilizador

## Notas importantes

- `http://127.0.0.1:8000` e `http://127.0.0.1:5001` so funcionam se a app estiver na mesma maquina.
- Em Android/iPhone real, usa o IP do computador na rede local.
- A app abre com login e guarda a sessao localmente por conta.
- Em `Configuracoes > LLM` podes alternar entre `Ollama` e `OpenAI`.
- O modelo OpenAI e escolhido por `dropdown`, nao por texto livre.
- A chave OpenAI deixou de ser configurada no Flutter; o backend deve ter `OPENAI_API_KEY`.
- Se o Home Assistant estiver desligado nas configuracoes, a secao de dispositivos Home Assistant desaparece do menu lateral.

## Comandos uteis

```powershell
flutter test
flutter analyze
```
