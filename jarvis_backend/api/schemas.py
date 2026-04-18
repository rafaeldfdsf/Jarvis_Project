from pydantic import BaseModel
from typing import Optional, Dict, Any


class ChatRequest(BaseModel):
    session_id: str
    message: str


class SessionResponse(BaseModel):
    session_id: str
    tools: list
    desktop_tools_enabled: bool


class ChatResponse(BaseModel):
    session_id: str
    reply: str
    tool_call: Optional[Dict[str, Any]] = None
    tool_result: Optional[Dict[str, Any]] = None
    desktop_tools_enabled: bool
    client_action: Optional[Dict[str, Any]] = None


class VoiceTurnResponse(ChatResponse):
    transcript: str = ''
    platform: Optional[str] = None
    locale: Optional[str] = None


class MemoryEntryResponse(BaseModel):
    key: str
    value: str
    type: str
    label: str
    index: Optional[int] = None


class MemoryUpdateRequest(BaseModel):
    value: str