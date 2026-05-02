"""Configuracao central da aplicacao."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import os


BASE_DIR = Path(__file__).resolve().parent
ENV_FILE = BASE_DIR / ".env"


def _load_dotenv(path: Path) -> None:
    if not path.exists():
        return

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


def _env_str(*names: str, default: str) -> str:
    for name in names:
        value = os.getenv(name)
        if value is not None and value.strip():
            return value.strip()
    return default


def _env_int(*names: str, default: int) -> int:
    raw_value = _env_str(*names, default=str(default))
    try:
        return int(raw_value)
    except ValueError:
        return default


def _env_float(*names: str, default: float) -> float:
    raw_value = _env_str(*names, default=str(default))
    try:
        return float(raw_value)
    except ValueError:
        return default


def _env_bool(*names: str, default: bool) -> bool:
    raw_value = _env_str(*names, default="true" if default else "false").lower()
    if raw_value in {"1", "true", "yes", "on"}:
        return True
    if raw_value in {"0", "false", "no", "off"}:
        return False
    return default


_load_dotenv(ENV_FILE)


@dataclass(frozen=True)
class Settings:
    ollama_url: str
    model: str
    sample_rate: int
    max_turns: int
    db_file: Path
    llm_timeout_seconds: float
    weather_timeout_seconds: float
    desktop_agent_url: str
    desktop_agent_timeout_seconds: float
    openai_timeout_seconds: float
    openai_transcription_model: str
    openai_vision_model: str
    openai_tts_model: str
    openai_tts_voice: str
    openai_tts_instructions: str
    api_token: str
    log_level: str
    app_name: str
    smtp_host: str
    smtp_port: int
    smtp_username: str
    smtp_password: str
    smtp_from_email: str
    smtp_from_name: str
    smtp_use_tls: bool

    @property
    def api_auth_enabled(self) -> bool:
        return bool(self.api_token)

    @property
    def smtp_enabled(self) -> bool:
        return bool(
            self.smtp_host and
            self.smtp_port > 0 and
            self.smtp_from_email
        )


settings = Settings(
    ollama_url=_env_str("JARVIS_OLLAMA_URL", "OLLAMA_URL", default="http://127.0.0.1:11434"),
    model=_env_str("JARVIS_OLLAMA_MODEL", "OLLAMA_MODEL", "MODEL", default="llama3.1:8b"),
    sample_rate=_env_int("JARVIS_SAMPLE_RATE", "SAMPLE_RATE", default=16000),
    max_turns=_env_int("JARVIS_MAX_TURNS", "MAX_TURNS", default=6),
    db_file=BASE_DIR / _env_str("JARVIS_DB_FILE", "DB_FILE", default="memory.db"),
    llm_timeout_seconds=_env_float("JARVIS_LLM_TIMEOUT_SECONDS", default=60.0),
    weather_timeout_seconds=_env_float("JARVIS_WEATHER_TIMEOUT_SECONDS", default=10.0),
    desktop_agent_url=_env_str(
        "JARVIS_DESKTOP_AGENT_URL",
        default="http://127.0.0.1:5001",
    ),
    desktop_agent_timeout_seconds=_env_float(
        "JARVIS_DESKTOP_AGENT_TIMEOUT_SECONDS",
        default=2.5,
    ),
    openai_timeout_seconds=_env_float("JARVIS_OPENAI_TIMEOUT_SECONDS", default=45.0),
    openai_transcription_model=_env_str(
        "JARVIS_OPENAI_STT_MODEL",
        default="whisper-1",
    ),
    openai_vision_model=_env_str(
        "JARVIS_OPENAI_VISION_MODEL",
        default="gpt-4.1-mini",
    ),
    openai_tts_model=_env_str("JARVIS_OPENAI_TTS_MODEL", default="gpt-4o-mini-tts"),
    openai_tts_voice=_env_str("JARVIS_OPENAI_TTS_VOICE", default="cedar"),
    openai_tts_instructions=_env_str(
        "JARVIS_OPENAI_TTS_INSTRUCTIONS",
        default=(
            "Speak in European Portuguese (pt-PT) with a natural, warm, conversational tone. "
            "Use clear pronunciation, moderate pace, subtle pauses, and human expressiveness. "
            "Avoid sounding robotic, overly formal, or like an announcer."
        ),
    ),
    api_token=_env_str("JARVIS_API_TOKEN", default=""),
    log_level=_env_str("JARVIS_LOG_LEVEL", "LOG_LEVEL", default="INFO").upper(),
    app_name=_env_str("JARVIS_APP_NAME", default="Jarvis"),
    smtp_host=_env_str("JARVIS_SMTP_HOST", default=""),
    smtp_port=_env_int("JARVIS_SMTP_PORT", default=587),
    smtp_username=_env_str("JARVIS_SMTP_USERNAME", default=""),
    smtp_password=_env_str("JARVIS_SMTP_PASSWORD", default=""),
    smtp_from_email=_env_str("JARVIS_SMTP_FROM_EMAIL", default=""),
    smtp_from_name=_env_str("JARVIS_SMTP_FROM_NAME", default="Jarvis"),
    smtp_use_tls=_env_bool("JARVIS_SMTP_USE_TLS", default=True),
)


# Backward-compatible exports for the existing modules.
OLLAMA_URL = settings.ollama_url
MODEL = settings.model
SAMPLE_RATE = settings.sample_rate
MAX_TURNS = settings.max_turns
DB_FILE = str(settings.db_file)
LLM_TIMEOUT_SECONDS = settings.llm_timeout_seconds
WEATHER_TIMEOUT_SECONDS = settings.weather_timeout_seconds
DESKTOP_AGENT_URL = settings.desktop_agent_url
DESKTOP_AGENT_TIMEOUT_SECONDS = settings.desktop_agent_timeout_seconds
OPENAI_TIMEOUT_SECONDS = settings.openai_timeout_seconds
OPENAI_TRANSCRIPTION_MODEL = settings.openai_transcription_model
OPENAI_VISION_MODEL = settings.openai_vision_model
OPENAI_TTS_MODEL = settings.openai_tts_model
OPENAI_TTS_VOICE = settings.openai_tts_voice
OPENAI_TTS_INSTRUCTIONS = settings.openai_tts_instructions
API_TOKEN = settings.api_token
LOG_LEVEL = settings.log_level
APP_NAME = settings.app_name

# Flag global usada para interromper o TTS (barge-in)
STOP_TTS = False
