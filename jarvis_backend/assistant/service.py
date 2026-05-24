"""Nucleo reutilizavel do assistente para modo local e modo servidor."""

from __future__ import annotations

from dataclasses import dataclass, field
import json
import re
import unicodedata
from datetime import datetime
from threading import Lock
from uuid import uuid4

from config import MAX_TURNS
from llm.service import call_llm
from logging_utils import get_logger, log_event
from memory.extract import extract_user_facts
from memory.user_memory import (
    clear_memory,
    delete_preference,
    delete_reminder,
    init_db,
    load_facts,
)
from prompts.system_prompt import build_system_prompt
from tools.executor import execute_tool, extract_tool_call, parse_day
from tools.registry import available_tools
from tools.weather import CITY_COORDS


logger = get_logger(__name__)

WEEKDAYS_PT = (
    "segunda-feira",
    "terca-feira",
    "quarta-feira",
    "quinta-feira",
    "sexta-feira",
    "sabado",
    "domingo",
)

MONTHS_PT = (
    "janeiro",
    "fevereiro",
    "marco",
    "abril",
    "maio",
    "junho",
    "julho",
    "agosto",
    "setembro",
    "outubro",
    "novembro",
    "dezembro",
)


def normalize_text(text: str) -> str:
    normalized = unicodedata.normalize("NFD", (text or "").lower().strip())
    return "".join(ch for ch in normalized if unicodedata.category(ch) != "Mn")


def build_time_reply(now: datetime) -> str:
    if now.hour == 0 and now.minute == 0:
        return "E meia-noite."

    if now.hour == 0:
        if now.minute == 1:
            return "E meia-noite e 1 minuto."
        return f"E meia-noite e {now.minute} minutos."

    if now.hour == 12 and now.minute == 0:
        return "E meio-dia."

    if now.hour == 12:
        if now.minute == 1:
            return "E meio-dia e 1 minuto."
        return f"E meio-dia e {now.minute} minutos."

    if now.hour == 1:
        if now.minute == 0:
            return "E 1 hora."
        if now.minute == 1:
            return "E 1 hora e 1 minuto."
        return f"E 1 hora e {now.minute} minutos."

    if now.minute == 0:
        return f"Sao {now.hour} horas."

    if now.minute == 1:
        return f"Sao {now.hour} horas e 1 minuto."

    return f"Sao {now.hour} horas e {now.minute} minutos."


def build_date_reply(now: datetime) -> str:
    weekday = WEEKDAYS_PT[now.weekday()]
    month = MONTHS_PT[now.month - 1]
    return f"Hoje e {weekday}, {now.day} de {month} de {now.year}."


def build_weekday_reply(now: datetime) -> str:
    return f"Hoje e {WEEKDAYS_PT[now.weekday()]}."


def matches_memory_clear_command(msg: str) -> bool:
    clear_verbs = ("limpa", "limpar", "esquece", "esquecer", "apaga", "apagar")
    memory_terms = ("memoria", "lembretes", "preferencias")
    return any(verb in msg for verb in clear_verbs) and any(
        term in msg for term in memory_terms
    )


def matches_close_window_command(msg: str) -> bool:
    return re.fullmatch(
        r"(?:podes\s+)?(?:fecha|fechar)\s+(?:a\s+)?(?:esta\s+)?janela(?:\s+ativa)?(?:\s+por favor)?",
        msg,
    ) is not None


def matches_close_tab_command(msg: str) -> bool:
    return any(token in msg for token in ("fecha", "fechar", "close")) and any(
        token in msg for token in ("aba", "tab")
    )


def extract_youtube_query(msg: str) -> str | None:
    if "youtube" not in msg:
        return None

    if not any(
        token in msg
        for token in ("abre", "abrir", "toca", "tocar", "poe", "por", "pesquisa", "procur")
    ):
        return None

    match = re.search(
        r"(?:abre|abrir|toca|tocar|poe|por|pesquisa|procurar)\s+(.+?)\s+(?:no\s+youtube|na\s+youtube|youtube)$",
        msg,
    )
    if not match:
        return None

    query = match.group(1).strip()
    query = re.sub(
        r"^(?:(?:uma|um|a|o)\s+)?(?:musica|video)\s*(?:dos|das|do|da|de)?\s*",
        "",
        query,
    ).strip()
    query = re.sub(r"^(?:pesquisa|procura)\s+por\s+", "", query).strip()
    return query or None


def build_client_action(tool_call: dict) -> dict | None:
    tool_name = tool_call.get("tool_name")
    args = tool_call.get("arguments", {}) or {}

    if not isinstance(args, dict):
        return None

    def cleaned_value(key: str) -> str:
        value = args.get(key)
        return value.strip() if isinstance(value, str) else ""

    def build_pc_action(action_name: str, extra: dict | None = None) -> dict:
        payload = {}
        for key, value in (extra or {}).items():
            if isinstance(value, str):
                value = value.strip()
            if value not in (None, ""):
                payload[key] = value

        return {
            "type": "pc_action",
            "action": action_name,
            "arguments": payload,
        }

    if tool_name in {"open_app", "open_youtube"}:
        app_name = (args.get("app_name") or "").strip().lower()

        if tool_name == "open_youtube":
            app_name = "youtube"

        if not app_name:
            return None

        if app_name in {"youtube", "yt"}:
            return {
                "type": "open_url",
                "url": "https://www.youtube.com",
            }

        return {
            "type": "open_app",
            "app_name": app_name,
        }

    if tool_name == "open_website":
        url = (args.get("url") or "").strip()
        if not url:
            return None

        if not url.startswith("http"):
            url = "https://" + url

        return {
            "type": "open_url",
            "url": url,
        }

    if tool_name == "control_computer":
        raw_action = cleaned_value("action")
        normalized_action = normalize_text(raw_action)
        action_key = normalized_action.replace(" ", "_")
        action_aliases = {
            "close_application": "close_app",
            "close_browser_tab": "close_tab",
            "close_current_tab": "close_tab",
            "close_youtube_tab": "close_tab",
            "search_youtube": "youtube_search",
            "play_youtube": "youtube_search",
            "play_music_on_youtube": "youtube_search",
            "open_music_on_youtube": "youtube_search",
            "switch_window": "activate_window",
            "focus_window": "activate_window",
            "open_website": "open_url",
        }
        action_name = action_aliases.get(action_key, action_key)

        target_value = cleaned_value("target")
        action_args = {
            "app_name": cleaned_value("app_name"),
            "window_title": cleaned_value("window_title"),
            "url": cleaned_value("url"),
            "query": cleaned_value("query"),
            "text": cleaned_value("text"),
            "keys": cleaned_value("keys"),
        }

        if target_value:
            if action_name in {"open_app", "close_app"} and not action_args["app_name"]:
                action_args["app_name"] = target_value
            elif action_name in {"close_window", "activate_window", "minimize_window"} and not action_args["window_title"]:
                action_args["window_title"] = target_value
            elif action_name == "youtube_search" and not action_args["query"]:
                action_args["query"] = target_value
            elif action_name == "open_url" and not action_args["url"]:
                action_args["url"] = target_value
            elif action_name == "type_text" and not action_args["text"]:
                action_args["text"] = target_value
            elif action_name == "press_keys" and not action_args["keys"]:
                action_args["keys"] = target_value

        inferred_text = normalize_text(
            " ".join(
                value
                for value in [
                    raw_action,
                    target_value,
                    action_args["app_name"],
                    action_args["window_title"],
                    action_args["query"],
                    action_args["text"],
                ]
                if value
            )
        )
        if action_name not in {
            "open_app",
            "open_url",
            "close_window",
            "close_app",
            "close_tab",
            "type_text",
            "press_keys",
            "youtube_search",
            "activate_window",
            "minimize_window",
        }:
            if any(token in inferred_text for token in ("aba", "tab")) and any(
                token in inferred_text for token in ("fecha", "fechar", "close")
            ):
                action_name = "close_tab"
            elif "youtube" in inferred_text and any(
                token in inferred_text
                for token in ("musica", "video", "toca", "abre", "pesquisa", "procur")
            ):
                action_name = "youtube_search"
            elif any(token in inferred_text for token in ("app", "aplicacao", "programa")) and any(
                token in inferred_text for token in ("fecha", "fechar", "close", "encerrar")
            ):
                action_name = "close_app"
            elif any(token in inferred_text for token in ("janela", "window")) and any(
                token in inferred_text for token in ("fecha", "fechar", "close")
            ):
                action_name = "close_window"

        if action_name == "youtube_search" and not action_args["query"]:
            fallback_query = target_value or action_args["text"] or raw_action
            fallback_query = re.sub(r"\byoutube\b", "", normalize_text(fallback_query)).strip()
            fallback_query = re.sub(
                r"^(?:abre|abrir|toca|tocar|poe|por|pesquisa|procurar)\s+",
                "",
                fallback_query,
            ).strip()
            fallback_query = re.sub(
                r"^(?:uma|um|a|o)\s+(?:musica|video)\s*(?:dos|das|do|da|de)?\s*",
                "",
                fallback_query,
            ).strip()
            if fallback_query:
                action_args["query"] = fallback_query

        supported_actions = {
            "open_app",
            "open_url",
            "close_window",
            "close_app",
            "close_tab",
            "type_text",
            "press_keys",
            "youtube_search",
            "activate_window",
            "minimize_window",
        }
        if action_name not in supported_actions:
            return None

        return build_pc_action(action_name, action_args)

    return None


@dataclass
class SessionState:
    messages: list[dict]
    user_id: str | None = None
    lock: Lock = field(default_factory=Lock)


class AssistantService:
    """Mantem sessoes em memoria e processa mensagens do utilizador."""

    def __init__(self, enable_desktop_tools: bool = False):
        self.enable_desktop_tools = enable_desktop_tools
        self.available_tools = available_tools(
            enable_local_automation=enable_desktop_tools
        )
        self.sessions: dict[str, SessionState] = {}
        self.sessions_lock = Lock()
        init_db()

    def create_session(self, user_id: str | None = None) -> dict:
        session_id = str(uuid4())
        state = SessionState(
            messages=[
                {"role": "system", "content": build_system_prompt(self.available_tools, user_id=user_id)}
            ],
            user_id=(user_id or "").strip() or None,
        )

        with self.sessions_lock:
            self.sessions[session_id] = state

        log_event(logger, 20, "session_created", session_id=session_id)
        return {
            "session_id": session_id,
            "tools": self.available_tools,
            "desktop_tools_enabled": self.enable_desktop_tools,
        }

    def delete_session(self, session_id: str) -> bool:
        with self.sessions_lock:
            deleted = self.sessions.pop(session_id, None) is not None

        log_event(logger, 20, "session_deleted", session_id=session_id, deleted=deleted)
        return deleted

    def _get_session_state(self, session_id: str) -> SessionState:
        with self.sessions_lock:
            state = self.sessions.get(session_id)

        if state is None:
            log_event(logger, 30, "session_missing", session_id=session_id)
            raise KeyError(f"Sessao desconhecida: {session_id}")

        return state

    def chat(self, session_id: str, user_message: str) -> dict:
        if not user_message or not user_message.strip():
            raise ValueError("A mensagem do utilizador nao pode estar vazia.")

        session_state = self._get_session_state(session_id)

        with session_state.lock:
            messages = session_state.messages
            user_message = user_message.strip()
            msg = normalize_text(user_message)

            def response_payload(reply: str, tool_call=None, tool_result=None, client_action=None):
                log_event(
                    logger,
                    20,
                    "chat_completed",
                    session_id=session_id,
                    reply_length=len(reply),
                    tool_name=(tool_result or {}).get("tool_name") if isinstance(tool_result, dict) else None,
                    client_action_type=(client_action or {}).get("type") if isinstance(client_action, dict) else None,
                )
                return {
                    "session_id": session_id,
                    "reply": reply,
                    "tool_call": tool_call,
                    "tool_result": tool_result,
                    "desktop_tools_enabled": self.enable_desktop_tools,
                    "client_action": client_action,
                }

            if any(x in msg for x in ["que horas", "horas sao", "as horas", "hora atual"]):
                return response_payload(build_time_reply(datetime.now().astimezone()))

            if any(
                x in msg
                for x in [
                    "que dia e hoje",
                    "qual e a data",
                    "data de hoje",
                    "em que dia estamos",
                    "dia de hoje",
                ]
            ):
                return response_payload(build_date_reply(datetime.now().astimezone()))

            if any(x in msg for x in ["que dia da semana", "dia da semana"]):
                return response_payload(build_weekday_reply(datetime.now().astimezone()))

            if matches_close_window_command(msg):
                return response_payload(
                    "A fechar a janela.",
                    client_action={"type": "pc_action", "action": "close_window"},
                )

            if matches_close_tab_command(msg):
                return response_payload(
                    "A fechar a aba.",
                    client_action={
                        "type": "pc_action",
                        "action": "close_tab",
                        "arguments": {},
                    },
                )

            youtube_query = extract_youtube_query(msg)
            if youtube_query:
                return response_payload(
                    "A pesquisar no YouTube.",
                    client_action={
                        "type": "pc_action",
                        "action": "youtube_search",
                        "arguments": {"query": youtube_query},
                    },
                )

            if "volume" in msg and ("aumenta" in msg or "subir" in msg):
                return response_payload(
                    "A aumentar o volume.",
                    client_action={"type": "pc_action", "action": "volume_up"},
                )

            if "volume" in msg and ("baixa" in msg or "diminuir" in msg):
                return response_payload(
                    "A baixar o volume.",
                    client_action={"type": "pc_action", "action": "volume_down"},
                )

            if "screenshot" in msg or "captura" in msg:
                return response_payload(
                    "A tirar screenshot.",
                    client_action={"type": "pc_action", "action": "screenshot"},
                )

            if any(x in msg for x in ["memoria", "lembretes", "preferencias"]) and any(
                y in msg for y in ["mostra", "lista", "ver", "mostrar"]
            ):
                facts = load_facts(user_id=session_state.user_id)
                table_format = "tabela" in msg or "table" in msg

                if table_format:
                    reply_lines = ["| ID | Tipo | Conteudo |", "|----|------|----------|"]
                    if "name" in facts:
                        reply_lines.append(f"| - | Nome | {facts['name']} |")

                    for i, pref in enumerate(facts.get("preferences", []), 1):
                        reply_lines.append(f"| {i} | Preferencia | {pref} |")

                    for i, rem in enumerate(facts.get("reminders", []), 1):
                        reply_lines.append(f"| {i} | Lembrete | {rem} |")

                    if not facts.get("preferences") and not facts.get("reminders") and "name" not in facts:
                        reply_lines.append("| - | - | Nenhuma informacao guardada |")

                    return response_payload("\n".join(reply_lines))

                response_parts = []
                if "name" in facts:
                    response_parts.append(f"Nome guardado: {facts['name']}")

                preferences = facts.get("preferences", [])
                if preferences:
                    response_parts.append("Preferencias:")
                    for i, pref in enumerate(preferences, 1):
                        response_parts.append(f"  {i}. {pref}")
                else:
                    response_parts.append("Nenhuma preferencia guardada.")

                reminders = facts.get("reminders", [])
                if reminders:
                    response_parts.append("Lembretes:")
                    for i, rem in enumerate(reminders, 1):
                        response_parts.append(f"  {i}. {rem}")
                else:
                    response_parts.append("Nenhum lembrete guardado.")

                return response_payload("\n".join(response_parts))

            match = re.search(r"(?:remove|remover)\s+preferencia\s+(\d+)", msg, re.IGNORECASE)
            if match:
                index = int(match.group(1))
                delete_preference(index, user_id=session_state.user_id)
                return response_payload(f"Preferencia {index} removida da memoria.")

            match = re.search(r"(?:remove|remover)\s+lembrete\s+(\d+)", msg, re.IGNORECASE)
            if match:
                index = int(match.group(1))
                delete_reminder(index, user_id=session_state.user_id)
                return response_payload(f"Lembrete {index} removido da memoria.")

            if matches_memory_clear_command(msg):
                deleted_count = clear_memory(user_id=session_state.user_id)
                reply = "Toda a memoria foi limpa."
                if deleted_count == 0:
                    reply = "Nao havia memoria guardada para limpar."
                return response_payload(reply)

            if "tempo" in msg:
                day_offset = parse_day(msg)
                city = "Lisboa"

                facts = load_facts(user_id=session_state.user_id)
                for pref in facts.get("preferences", []):
                    if "tempo" in pref.lower() and "caldas da rainha" in pref.lower():
                        city = "caldas da rainha"
                        break

                for known_city in CITY_COORDS.keys():
                    if known_city in msg:
                        city = known_city
                        break

                executed_tool = execute_tool(
                    "get_weather",
                    {"city": city, "day_offset": day_offset},
                )
                tool_call = {
                    "type": "tool_call",
                    "tool_name": "get_weather",
                    "arguments": {"city": city, "day_offset": day_offset},
                }

                messages.append({"role": "user", "content": user_message})
                messages.append({"role": "assistant", "content": json.dumps(tool_call, ensure_ascii=False)})
                messages.append({"role": "tool", "content": json.dumps(executed_tool, ensure_ascii=False)})
                return response_payload(
                    call_llm(messages, user_id=session_state.user_id),
                    tool_call=tool_call,
                    tool_result=executed_tool,
                )

            messages.append({"role": "user", "content": user_message})
            extract_user_facts(user_message, user_id=session_state.user_id)
            messages[0]["content"] = build_system_prompt(
                self.available_tools,
                user_id=session_state.user_id,
            )

            first_reply = call_llm(messages, user_id=session_state.user_id)
            parsed = None
            try:
                parsed = json.loads(first_reply)
            except Exception:
                parsed = None

            tool_call = parsed if isinstance(parsed, dict) and parsed.get("type") == "tool_call" else None
            if not tool_call:
                tool_call = extract_tool_call(first_reply)

            client_action = None
            executed_tool = None
            reply = first_reply

            if tool_call:
                try:
                    args = tool_call.get("arguments", {})
                    if isinstance(args, str):
                        try:
                            args = json.loads(args)
                        except Exception:
                            args = {}
                    if not isinstance(args, dict):
                        args = {}

                    tool_call["arguments"] = args
                    tool_name = tool_call.get("tool_name")

                    if tool_name in {"open_website", "open_app", "open_youtube", "control_computer"}:
                        client_action = build_client_action(tool_call)
                        if client_action:
                            executed_tool = {
                                "tool_name": tool_name,
                                "ok": True,
                                "data": "Acao enviada para o cliente.",
                            }
                            reply = "A executar a acao."
                        else:
                            executed_tool = {
                                "tool_name": tool_name,
                                "ok": False,
                                "data": "Erro ao converter acao.",
                            }
                            reply = executed_tool["data"]
                    else:
                        executed_tool = execute_tool(
                            tool_name,
                            args,
                            allow_desktop_tools=self.enable_desktop_tools,
                            user_id=session_state.user_id,
                        )
                        messages.append({"role": "assistant", "content": json.dumps(tool_call, ensure_ascii=False)})
                        messages.append({"role": "tool", "content": json.dumps(executed_tool, ensure_ascii=False)})
                        if executed_tool.get("ok"):
                            reply = call_llm(messages, user_id=session_state.user_id)
                        else:
                            reply = f"Nao consegui executar: {executed_tool.get('data')}"
                except Exception as exc:
                    log_event(
                        logger,
                        40,
                        "tool_execution_failed",
                        session_id=session_id,
                        tool_name=tool_call.get("tool_name"),
                        error=str(exc),
                    )
                    reply = f"Erro ao executar ferramenta: {str(exc)}"

            messages.append({"role": "assistant", "content": reply})
            if len(messages) > 1 + MAX_TURNS * 2:
                messages[:] = messages[:1] + messages[-MAX_TURNS * 2 :]

            return response_payload(reply, tool_call=tool_call, tool_result=executed_tool, client_action=client_action)
