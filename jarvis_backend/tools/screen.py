from __future__ import annotations

import base64
import io

import requests
from openai import OpenAI

from config import settings


SCREEN_ANALYSIS_SYSTEM_PROMPT = (
    "Analisa capturas de ecra de computador e responde em portugues de Portugal. "
    "Foca-te em responder diretamente ao pedido do utilizador. "
    "Se a imagem nao for suficiente ou o texto estiver ilegivel, diz isso claramente. "
    "Nao inventes detalhes que nao sejam visiveis."
)


def _active_window_title_local() -> str | None:
    try:
        import pygetwindow as gw
    except Exception:
        return None

    try:
        window = gw.getActiveWindow()
    except Exception:
        return None

    title = (window.title or "").strip() if window else ""
    return title or None


def _capture_screen_locally() -> tuple[bytes, dict]:
    try:
        import pyautogui
    except Exception as exc:
        raise RuntimeError("Nao consegui importar pyautogui para capturar o ecra.") from exc

    try:
        screenshot = pyautogui.screenshot()
    except Exception as exc:
        raise RuntimeError("Falha ao capturar o ecra localmente.") from exc

    buffer = io.BytesIO()
    screenshot.save(buffer, format="PNG")
    return buffer.getvalue(), {
        "source": "local",
        "active_window_title": _active_window_title_local(),
    }


def _capture_screen_from_agent() -> tuple[bytes, dict]:
    agent_url = (settings.desktop_agent_url or "").strip().rstrip("/")
    if not agent_url:
        raise RuntimeError("URL do agente desktop nao configurada.")

    try:
        response = requests.get(
            f"{agent_url}/screen/capture",
            timeout=settings.desktop_agent_timeout_seconds,
        )
        response.raise_for_status()
        payload = response.json()
    except requests.RequestException as exc:
        raise RuntimeError("Nao consegui obter a captura de ecra atraves do agente.") from exc
    except ValueError as exc:
        raise RuntimeError("O agente desktop devolveu uma resposta invalida.") from exc

    if payload.get("ok") is not True:
        raise RuntimeError(payload.get("error") or "O agente desktop nao conseguiu capturar o ecra.")

    encoded_image = (payload.get("image_base64") or "").strip()
    if not encoded_image:
        raise RuntimeError("O agente desktop nao devolveu a imagem capturada.")

    try:
        image_bytes = base64.b64decode(encoded_image)
    except Exception as exc:
        raise RuntimeError("A imagem recebida do agente desktop esta corrompida.") from exc

    return image_bytes, {
        "source": "agent",
        "active_window_title": payload.get("active_window_title"),
    }


def _capture_screen() -> tuple[bytes, dict]:
    try:
        return _capture_screen_from_agent()
    except RuntimeError:
        return _capture_screen_locally()


def _extract_completion_text(completion) -> str:
    try:
        message = completion.choices[0].message
    except Exception as exc:
        raise RuntimeError("O modelo de visao respondeu num formato inesperado.") from exc

    content = getattr(message, "content", "")
    if isinstance(content, str):
        return content.strip()

    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, str):
                parts.append(item)
                continue

            text = getattr(item, "text", None)
            if text:
                parts.append(str(text))

        return "\n".join(part.strip() for part in parts if part and part.strip())

    return str(content).strip()


def analyze_screen(question: str) -> str:
    clean_question = (question or "").strip()
    if not clean_question:
        clean_question = "Descreve de forma breve o que esta visivel no ecra."

    image_bytes, metadata = _capture_screen()
    image_data_url = f"data:image/png;base64,{base64.b64encode(image_bytes).decode('ascii')}"
    active_window_title = (metadata.get("active_window_title") or "").strip()

    user_prompt = (
        f"Pedido do utilizador: {clean_question}\n"
        "Responde de forma objetiva e curta. "
        "Se estiveres a ler texto pequeno, cita apenas o que conseguires ver com seguranca."
    )
    if active_window_title:
        user_prompt += f"\nJanela ativa: {active_window_title}"

    client = OpenAI(timeout=settings.openai_timeout_seconds)

    try:
        completion = client.chat.completions.create(
            model=settings.openai_vision_model,
            messages=[
                {"role": "system", "content": SCREEN_ANALYSIS_SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": user_prompt},
                        {"type": "image_url", "image_url": {"url": image_data_url}},
                    ],
                },
            ],
            max_tokens=350,
        )
    except Exception as exc:
        raise RuntimeError("Falha ao analisar a captura de ecra com o modelo de visao.") from exc

    answer = _extract_completion_text(completion)
    if not answer:
        raise RuntimeError("O modelo de visao nao devolveu texto utilizavel.")

    if active_window_title:
        return f"Janela ativa: {active_window_title}. {answer}"

    return answer
