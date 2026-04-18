from typing import Any, Dict


def tool_result(name: str, ok: bool, data: Any) -> Dict[str, Any]:
    return {
        "tool_name": name,
        "ok": ok,
        "data": data,
    }