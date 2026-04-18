"""Ponto de entrada da aplicacao em modo voz local ou modo servidor HTTP."""

import argparse

from assistant.service import AssistantService


def run_voice_mode():
    from audio.stt import calibrate_noise, listen
    from audio.tts import speak
    from audio.wakeword import wait_for_wake_word

    assistant = AssistantService(enable_desktop_tools=True)
    session = assistant.create_session()
    session_id = session["session_id"]

    calibrate_noise()

    print("Assistente com voz iniciado")
    print("Diz 'Jarvis' para comecar a falar\n")

    while True:
        wait_for_wake_word()
        speak("Sim?")

        while True:
            user = listen()

            if not user:
                continue

            if user.lower() in {"sair", "exit", "quit"}:
                speak("Ok, fico a espera.")
                break

            try:
                response = assistant.chat(session_id, user)
            except Exception as exc:
                print(f"Erro no assistente: {exc}")
                speak("Houve um erro ao processar o pedido.")
                continue

            reply = response["reply"]
            print(f"\nAssistente: {reply}\n")
            speak(reply)


def run_server_mode(host: str, port: int):
    import uvicorn
    from api.server import app

    uvicorn.run(app, host=host, port=port)


def main():
    parser = argparse.ArgumentParser(
        description="Jarvis Codex em modo voz local ou API HTTP para clientes externos."
    )
    parser.add_argument(
        "--mode",
        choices=("voice", "server"),
        default="voice",
        help="voice para assistente local; server para expor API HTTP.",
    )
    parser.add_argument("--host", default="0.0.0.0", help="Host da API no modo server.")
    parser.add_argument("--port", type=int, default=8000, help="Porta da API no modo server.")
    args = parser.parse_args()

    if args.mode == "server":
        run_server_mode(args.host, args.port)
        return

    run_voice_mode()


if __name__ == "__main__":
    main()
