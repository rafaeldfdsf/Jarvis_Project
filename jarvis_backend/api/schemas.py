from pydantic import BaseModel
from typing import Optional, Dict, Any


class ChatRequest(BaseModel):
    session_id: str
    message: str


class AuthRegisterRequest(BaseModel):
    email: str
    password: str
    display_name: str = ''


class AuthVerifyEmailRequest(BaseModel):
    email: str
    code: str


class AuthForgotPasswordRequest(BaseModel):
    email: str


class AuthResetPasswordRequest(BaseModel):
    email: str
    code: str
    new_password: str


class AuthLoginRequest(BaseModel):
    email: str
    password: str


class AuthUserResponse(BaseModel):
    id: str
    email: str
    display_name: str = ''
    created_at: str
    email_verified_at: str | None = None
    email_verified: bool = False


class AuthStatusResponse(BaseModel):
    ok: bool = True
    message: str
    email: str = ''
    email_sent: bool = False
    verification_required: bool = False


class AuthSessionResponse(BaseModel):
    access_token: str
    token_type: str = 'bearer'
    user: AuthUserResponse


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
    enabled: bool = True
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


class AppSettingEntryResponse(BaseModel):
    key: str
    value: str
    label: str
    updated_at: str = ''


class AppSettingsUpdateRequest(BaseModel):
    assistant_name: str = ''
    user_name: str = ''
    wake_word_phrase: str = ''
    wake_word_sensitivity: int = 40
    home_assistant_enabled: bool = False
    home_assistant_url: str = ''
    home_assistant_token: str = ''


class RegisteredDeviceResponse(BaseModel):
    device_id: str
    name: str
    device_type: str
    platform: str = ''
    location: str = ''
    is_active: bool
    preferred_for_wake_word: bool
    preferred_for_tts: bool
    preferred_for_desktop_control: bool
    connected: bool
    last_seen_at: str = ''
    last_error: str = ''
    metadata: Dict[str, Any] = {}
    capabilities: list[str] = []
    created_at: str = ''
    updated_at: str = ''


class RegisteredDeviceUpdateRequest(BaseModel):
    name: Optional[str] = None
    location: Optional[str] = None
    platform: Optional[str] = None
    is_active: Optional[bool] = None
    preferred_for_wake_word: Optional[bool] = None
    preferred_for_tts: Optional[bool] = None
    preferred_for_desktop_control: Optional[bool] = None
