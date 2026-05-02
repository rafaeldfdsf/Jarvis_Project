from datetime import datetime
import json
import re

from home_assistant.service import call_service, connection_status, list_entities
from home_assistant.devices import list_devices
from routines.service import (
    create_routine,
    delete_routine,
    list_routines,
    run_routine,
    update_routine,
)
from tools.desktop import control_computer, open_app, open_website, press_keys, type_text
from tools.registry import LOCAL_AUTOMATION_TOOL_NAMES
from tools.screen import analyze_screen
from tools.schemas import tool_result
from tools.weather import get_weather
from tools.web_search import search_web


def extract_tool_call(text: str):
    if not isinstance(text, str):
        return None

    text = text.strip()
    known_tool_names = {
        "get_home_assistant_status",
        "list_home_assistant_entities",
        "list_home_assistant_devices",
        "call_home_assistant_service",
        "get_weather",
        "search_web",
        "open_website",
        "open_app",
        "control_computer",
        "analyze_screen",
        "type_text",
        "press_keys",
        "list_routines",
        "create_routine",
        "update_routine",
        "delete_routine",
        "run_routine",
    }

    def normalize_tool_payload(data: dict) -> dict | None:
        if not isinstance(data, dict):
            return None

        if data.get("type") == "tool_call" and isinstance(data.get("tool_name"), str):
            return data

        legacy_tool_name = data.get("type")
        if isinstance(legacy_tool_name, str) and legacy_tool_name in known_tool_names:
            arguments = {
                key: value
                for key, value in data.items()
                if key not in {"type", "tool_name", "arguments"}
            }
            if isinstance(data.get("arguments"), dict):
                arguments.update(data["arguments"])
            return {
                "type": "tool_call",
                "tool_name": legacy_tool_name,
                "arguments": arguments,
            }

        return None

    def parse_json_fragment(fragment: str):
        try:
            data = json.loads(fragment)
        except json.JSONDecodeError:
            return None
        return normalize_tool_payload(data)

    if text.startswith("{") and text.endswith("}"):
        result = parse_json_fragment(text)
        if result:
            return result

    depth = 0
    in_string = False
    escaped = False
    start = None

    for i, ch in enumerate(text):
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue

        if ch == '"':
            in_string = True
            continue

        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
            continue

        if ch == "}":
            if depth > 0:
                depth -= 1
            if depth == 0 and start is not None:
                candidate = text[start : i + 1]
                result = parse_json_fragment(candidate)
                if result:
                    return result

    return None


def execute_tool(
    tool_name: str,
    arguments: dict,
    allow_desktop_tools: bool = True,
    user_id: str | None = None,
):
    try:
        if tool_name in LOCAL_AUTOMATION_TOOL_NAMES.union({'control_computer'}) and not allow_desktop_tools:
            return tool_result(
                tool_name,
                False,
                "Esta tool esta desativada neste modo de execucao.",
            )

        if tool_name == "get_home_assistant_status":
            return tool_result(tool_name, True, connection_status(user_id=user_id))

        if tool_name == "list_home_assistant_entities":
            domain = arguments.get("domain", "")
            return tool_result(tool_name, True, list_entities(domain=domain, user_id=user_id))

        if tool_name == "list_home_assistant_devices":
            domain = arguments.get("domain", "")
            return tool_result(tool_name, True, list_devices(domain=domain, user_id=user_id))

        if tool_name == "call_home_assistant_service":
            return tool_result(
                tool_name,
                True,
                call_service(
                    arguments.get("domain", ""),
                    arguments.get("service", ""),
                    entity_id=arguments.get("entity_id"),
                    service_data=arguments.get("service_data"),
                    user_id=user_id,
                ),
            )

        if tool_name == "get_weather":
            city = arguments.get("city", "Lisboa")
            day_offset = arguments.get("day_offset")
            if day_offset is None:
                text = arguments.get("text", "")
                day_offset = parse_day(text)
            try:
                day_offset = int(day_offset)
            except (TypeError, ValueError):
                day_offset = 1
            return tool_result(tool_name, True, get_weather(city, day_offset))

        if tool_name == "search_web":
            query = arguments.get("query", "")
            return tool_result(tool_name, True, search_web(query))

        if tool_name == "open_website":
            url = arguments.get("url", "")
            return tool_result(tool_name, True, open_website(url))

        if tool_name == "open_app":
            app_name = arguments.get("app_name", "")
            return tool_result(tool_name, True, open_app(app_name))

        if tool_name == "control_computer":
            action = arguments.get("action", "")
            return tool_result(
                tool_name,
                True,
                control_computer(action, arguments=arguments),
            )

        if tool_name == "analyze_screen":
            question = arguments.get("question", "")
            return tool_result(tool_name, True, analyze_screen(question))

        if tool_name == "type_text":
            text = arguments.get("text", "")
            return tool_result(tool_name, True, type_text(text))

        if tool_name == "press_keys":
            keys = arguments.get("keys", "")
            return tool_result(tool_name, True, press_keys(keys))

        if tool_name == "list_routines":
            return tool_result(tool_name, True, list_routines(user_id=user_id))

        if tool_name == "create_routine":
            return tool_result(
                tool_name,
                True,
                create_routine(
                    name=arguments.get("name", ""),
                    description=arguments.get("description", ""),
                    trigger_text=arguments.get("trigger_text", ""),
                    actions=arguments.get("actions"),
                    enabled=arguments.get("enabled", True) is not False,
                    user_id=user_id,
                ),
            )

        if tool_name == "update_routine":
            return tool_result(
                tool_name,
                True,
                update_routine(
                    arguments.get("routine_id", ""),
                    name=arguments.get("name", ""),
                    description=arguments.get("description", ""),
                    trigger_text=arguments.get("trigger_text", ""),
                    actions=arguments.get("actions"),
                    enabled=arguments.get("enabled", True) is not False,
                    user_id=user_id,
                ),
            )

        if tool_name == "delete_routine":
            deleted = delete_routine(arguments.get("routine_id", ""), user_id=user_id)
            return tool_result(tool_name, deleted, {"deleted": deleted})

        if tool_name == "run_routine":
            return tool_result(tool_name, True, run_routine(arguments.get("routine_id", ""), user_id=user_id))

        return tool_result(tool_name, False, f"Tool desconhecida: {tool_name}")

    except Exception as exc:
        return tool_result(tool_name, False, str(exc))


WEEKDAY_ALIASES = (
    (0, ("segunda-feira", "segunda feira", "segunda")),
    (1, ("terca-feira", "terca feira", "terca")),
    (2, ("quarta-feira", "quarta feira", "quarta")),
    (3, ("quinta-feira", "quinta feira", "quinta")),
    (4, ("sexta-feira", "sexta feira", "sexta")),
    (5, ("sabado",)),
    (6, ("domingo",)),
)


def parse_day(text, now: datetime | None = None):
    text = (text or "").lower()

    if "depois de amanha" in text:
        return 2

    if "amanha" in text:
        return 1

    if "hoje" in text:
        return 0

    today = (now or datetime.now().astimezone()).weekday()
    for weekday, aliases in WEEKDAY_ALIASES:
        if any(alias in text for alias in aliases):
            return (weekday - today) % 7

    return 0
