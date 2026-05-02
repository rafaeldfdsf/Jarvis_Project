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


class HomeAssistantStatusResponse(BaseModel):
    configured: bool
    connected: bool
    url: str = ''
    location_name: Optional[str] = None
    entity_count: int = 0
    message: str


class HomeAssistantDeviceResponse(BaseModel):
    entity_id: str
    domain: str
    friendly_name: str
    alias: str = ''
    state: str = ''
    attributes: Dict[str, Any] = {}
    last_seen_at: str
    updated_at: str


class HomeAssistantDeviceAliasUpdateRequest(BaseModel):
    alias: str = ''


class RoutineActionPayload(BaseModel):
    type: str
    label: Optional[str] = None
    domain: Optional[str] = None
    service: Optional[str] = None
    entity_id: Optional[str] = None
    target: Optional[str] = None
    message: Optional[str] = None
    text: Optional[str] = None
    service_data: Optional[Dict[str, Any]] = None


class RoutinePayload(BaseModel):
    name: str
    description: str = ''
    trigger_text: str = ''
    actions: list[RoutineActionPayload] = []
    enabled: bool = True


class RoutineResponse(BaseModel):
    id: str
    name: str
    description: str = ''
    trigger_text: str = ''
    actions: list[Dict[str, Any]] = []
    enabled: bool
    created_at: str
    updated_at: str


class RoutineRunResponse(BaseModel):
    routine_id: str
    routine_name: str
    results: list[Dict[str, Any]]
