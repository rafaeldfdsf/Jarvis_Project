from __future__ import annotations

import os
import re
import subprocess
import unicodedata
import urllib.parse
import webbrowser


KNOWN_APPS = {
    "calculadora": "calc",
    "bloco de notas": "notepad",
    "notepad": "notepad",
    "explorador": "explorer",
    "explorer": "explorer",
    "cmd": "cmd",
    "prompt de comandos": "cmd",
    "powershell": "powershell",
    "terminal": "wt",
    "google chrome": "chrome",
    "chrome": "chrome",
    "microsoft edge": "msedge",
    "edge": "msedge",
    "firefox": "firefox",
    "brave": "brave",
    "spotify": "spotify",
    "discord": "discord",
    "steam": "steam",
    "teams": "ms-teams",
    "vscode": "code",
    "visual studio code": "code",
    "word": "winword",
    "excel": "excel",
}

KNOWN_WEBSITES = {
    "youtube": "https://www.youtube.com",
    "google": "https://www.google.com",
    "gmail": "https://mail.google.com",
}

PROTECTED_WINDOW_TOKENS = ("jarvis", "codex", "flutter")


def _normalize_text(value: str) -> str:
    normalized = unicodedata.normalize("NFD", (value or "").lower().strip())
    without_accents = "".join(
        char for char in normalized if unicodedata.category(char) != "Mn"
    )
    compact = re.sub(r"[^a-z0-9]+", " ", without_accents)
    return re.sub(r"\s+", " ", compact).strip()


def _is_protected_title(title: str) -> bool:
    normalized = _normalize_text(title)
    return any(token in normalized for token in PROTECTED_WINDOW_TOKENS)


def _launch_app_target(target: str) -> None:
    last_error = None
    attempts = (
        (target, True),
        (["cmd", "/c", "start", "", target], False),
    )

    for command, use_shell in attempts:
        try:
            subprocess.Popen(command, shell=use_shell)
            return
        except Exception as exc:
            last_error = exc

    if last_error is not None:
        raise last_error


def _find_windows(window_title: str):
    import pygetwindow as gw

    normalized_target = _normalize_text(window_title)
    if not normalized_target:
        return []

    matches = []
    for window in gw.getAllWindows():
        title = (window.title or "").strip()
        if not title:
            continue
        if normalized_target in _normalize_text(title):
            matches.append(window)
    return matches


def open_website(url: str) -> str:
    clean_url = (url or "").strip()
    if not clean_url:
        raise ValueError("URL vazia.")

    if not clean_url.startswith("http"):
        clean_url = "https://" + clean_url
    webbrowser.open(clean_url)
    return f"A abrir {clean_url}."


def open_app(app_name: str) -> str:
    raw_name = (app_name or "").strip()
    if not raw_name:
        raise ValueError("Nome da aplicacao vazio.")

    normalized_name = _normalize_text(raw_name)

    if normalized_name in KNOWN_WEBSITES:
        return open_website(KNOWN_WEBSITES[normalized_name])

    target = KNOWN_APPS.get(normalized_name, raw_name)
    _launch_app_target(target)
    return f"A abrir {raw_name}."


def close_window(window_title: str | None = None) -> str:
    import pygetwindow as gw

    if window_title:
        windows = _find_windows(window_title)
    else:
        active_window = gw.getActiveWindow()
        windows = [active_window] if active_window is not None else []

    for window in windows:
        title = (window.title or "").strip()
        if title and _is_protected_title(title):
            continue

        try:
            window.close()
            label = title or "a janela ativa"
            return f"A fechar {label}."
        except Exception:
            continue

    if window_title:
        raise RuntimeError(f"Nao encontrei a janela '{window_title}'.")

    raise RuntimeError("Sem janela ativa para fechar.")


def close_app(app_name: str) -> str:
    import psutil

    raw_name = (app_name or "").strip()
    if not raw_name:
        raise ValueError("Nome da aplicacao vazio.")

    normalized_name = _normalize_text(raw_name)
    candidates = {normalized_name}
    mapped_target = KNOWN_APPS.get(normalized_name)
    if mapped_target:
        candidates.add(_normalize_text(mapped_target))

    closed_windows = 0
    try:
        for window in _find_windows(raw_name):
            title = (window.title or "").strip()
            if title and _is_protected_title(title):
                continue
            try:
                window.close()
                closed_windows += 1
            except Exception:
                continue
    except Exception:
        pass

    current_pid = os.getpid()
    terminated_processes = 0
    for process in psutil.process_iter(["pid", "name", "exe"]):
        if process.info.get("pid") == current_pid:
            continue

        process_name = process.info.get("name") or ""
        executable = process.info.get("exe") or ""
        normalized_fields = (_normalize_text(process_name), _normalize_text(executable))

        if not any(
            candidate and any(candidate in field for field in normalized_fields)
            for candidate in candidates
        ):
            continue

        if any(token in normalized_fields[0] for token in PROTECTED_WINDOW_TOKENS):
            continue

        try:
            process.terminate()
            terminated_processes += 1
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue

    if closed_windows or terminated_processes:
        return f"A fechar {raw_name}."

    raise RuntimeError(f"Nao encontrei a aplicacao '{raw_name}'.")


def activate_window(window_title: str) -> str:
    for window in _find_windows(window_title):
        title = (window.title or "").strip()
        try:
            if getattr(window, "isMinimized", False):
                window.restore()
            window.activate()
            return f"A mudar para {title or window_title}."
        except Exception:
            continue

    raise RuntimeError(f"Nao encontrei a janela '{window_title}'.")


def minimize_window(window_title: str | None = None) -> str:
    import pygetwindow as gw

    if window_title:
        windows = _find_windows(window_title)
    else:
        active_window = gw.getActiveWindow()
        windows = [active_window] if active_window is not None else []

    for window in windows:
        title = (window.title or "").strip()
        try:
            window.minimize()
            return f"A minimizar {title or 'a janela ativa'}."
        except Exception:
            continue

    if window_title:
        raise RuntimeError(f"Nao encontrei a janela '{window_title}'.")

    raise RuntimeError("Sem janela ativa para minimizar.")


def type_text(text: str) -> str:
    import pyautogui

    pyautogui.write(text, interval=0.02)
    return "Texto escrito."


def press_keys(keys: str) -> str:
    import pyautogui

    parts = [key.strip().lower() for key in (keys or "").split("+") if key.strip()]
    if not parts:
        raise ValueError("Nao recebi teclas para premir.")

    if len(parts) == 1:
        pyautogui.press(parts[0])
    else:
        pyautogui.hotkey(*parts)
    return f"Teclas premidas: {keys}."


def search_youtube(query: str) -> str:
    clean_query = (query or "").strip()
    if not clean_query:
        raise ValueError("Pesquisa vazia para o YouTube.")

    encoded_query = urllib.parse.quote_plus(clean_query)
    url = f"https://www.youtube.com/results?search_query={encoded_query}"
    webbrowser.open(url)
    return f"A pesquisar no YouTube por {clean_query}."


def control_computer(action: str, arguments: dict | None = None) -> str:
    args = arguments or {}
    clean_action = _normalize_text(action).replace(" ", "_")

    if clean_action in {"open_app", "abrir_app"}:
        return open_app(args.get("app_name", ""))

    if clean_action in {"open_url", "open_website", "abrir_site"}:
        return open_website(args.get("url", ""))

    if clean_action in {"close_window", "fechar_janela"}:
        return close_window(args.get("window_title"))

    if clean_action in {"close_app", "close_application", "fechar_app"}:
        return close_app(args.get("app_name", ""))

    if clean_action in {"close_tab", "close_browser_tab", "fechar_aba"}:
        return press_keys("ctrl+w")

    if clean_action in {"type_text", "write_text", "escrever_texto"}:
        return type_text(args.get("text", ""))

    if clean_action in {"press_keys", "keyboard_shortcut", "atalho"}:
        return press_keys(args.get("keys", ""))

    if clean_action in {"youtube_search", "search_youtube", "play_youtube"}:
        return search_youtube(args.get("query", ""))

    if clean_action in {"activate_window", "switch_window", "focus_window"}:
        return activate_window(args.get("window_title", ""))

    if clean_action in {"minimize_window", "minimizar_janela"}:
        return minimize_window(args.get("window_title"))

    raise RuntimeError(f"Acao de desktop desconhecida: {action}")
