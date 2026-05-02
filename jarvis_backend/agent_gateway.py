"""Gateway em memoria para agentes residentes ligados por WebSocket."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from typing import Any
from uuid import uuid4

from fastapi import WebSocket, WebSocketDisconnect

from device_registry import (
    get_device,
    list_registered_devices,
    set_device_connection_state,
    touch_device,
    upsert_device,
)
from logging_utils import get_logger, log_event


logger = get_logger(__name__)


@dataclass
class AgentConnection:
    device_id: str
    websocket: WebSocket
    capabilities: list[str] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)


class AgentGateway:
    def __init__(self) -> None:
        self._connections: dict[str, AgentConnection] = {}
        self._pending_results: dict[str, asyncio.Future] = {}
        self._lock = asyncio.Lock()

    async def handle_connection(self, websocket: WebSocket) -> None:
        await websocket.accept()
        hello = await websocket.receive_json()

        if hello.get("type") != "agent.hello":
            await websocket.close(code=1008, reason="Primeira mensagem invalida.")
            return

        device_id = str(hello.get("device_id") or "").strip()
        if not device_id:
            await websocket.close(code=1008, reason="device_id obrigatorio.")
            return

        capabilities = [
            capability.strip()
            for capability in hello.get("capabilities", [])
            if isinstance(capability, str) and capability.strip()
        ]
        metadata = hello.get("metadata") if isinstance(hello.get("metadata"), dict) else {}

        upsert_device(
            device_id=device_id,
            name=str(hello.get("device_name") or device_id).strip(),
            device_type=str(hello.get("device_type") or "unknown").strip(),
            platform=str(hello.get("platform") or "").strip(),
            location=str(hello.get("location") or "").strip(),
            metadata={
                **metadata,
                "agent_version": str(hello.get("agent_version") or "").strip(),
            },
            capabilities=capabilities,
            connected=True,
        )

        connection = AgentConnection(
            device_id=device_id,
            websocket=websocket,
            capabilities=capabilities,
            metadata=metadata,
        )

        async with self._lock:
            previous = self._connections.get(device_id)
            self._connections[device_id] = connection

        if previous is not None:
            try:
                await previous.websocket.close(code=1012, reason="Ligacao substituida.")
            except Exception:
                pass

        await websocket.send_json(
            {
                "type": "core.hello_ack",
                "device_id": device_id,
                "capabilities": capabilities,
            }
        )
        log_event(logger, 20, "agent_connected", device_id=device_id, capabilities=capabilities)

        try:
            while True:
                message = await websocket.receive_json()
                await self._handle_message(device_id, message)
        except WebSocketDisconnect:
            log_event(logger, 20, "agent_disconnected", device_id=device_id)
        except Exception as exc:
            log_event(logger, 40, "agent_connection_failed", device_id=device_id, error=str(exc))
            raise
        finally:
            set_device_connection_state(device_id, connected=False)
            async with self._lock:
                current = self._connections.get(device_id)
                if current is connection:
                    self._connections.pop(device_id, None)

    async def _handle_message(self, device_id: str, message: dict[str, Any]) -> None:
        message_type = str(message.get("type") or "").strip()
        touch_device(device_id)

        if message_type == "agent.result.action_completed":
            request_id = str(message.get("request_id") or "").strip()
            if not request_id:
                return

            async with self._lock:
                future = self._pending_results.pop(request_id, None)

            if future is not None and not future.done():
                future.set_result(message)
            return

        if message_type in {"agent.event.wake_word_detected", "agent.event.wake_word_heard"}:
            log_event(logger, 20, "agent_event", device_id=device_id, event_type=message_type)
            return

        if message_type == "agent.status":
            last_error = str(message.get("last_error") or "").strip()
            set_device_connection_state(device_id, connected=True, last_error=last_error)
            return

    async def dispatch_action(
        self,
        action_name: str,
        *,
        arguments: dict[str, Any] | None = None,
        target_device_id: str | None = None,
        timeout_seconds: float = 12.0,
    ) -> dict[str, Any]:
        connection = await self._select_executor(target_device_id)
        if connection is None:
            return {
                "ok": False,
                "error": "Nenhum agente executor ligado com capacidade desktop.control.",
            }

        request_id = str(uuid4())
        loop = asyncio.get_running_loop()
        future = loop.create_future()
        payload = {
            "type": "core.command.run_action",
            "request_id": request_id,
            "target_device_id": connection.device_id,
            "action": {
                "name": action_name,
                "arguments": arguments or {},
            },
        }

        async with self._lock:
            self._pending_results[request_id] = future

        try:
            await connection.websocket.send_json(payload)
            result = await asyncio.wait_for(future, timeout=timeout_seconds)
        except asyncio.TimeoutError:
            return {
                "ok": False,
                "error": f"Timeout ao esperar resposta do agente {connection.device_id}.",
                "device_id": connection.device_id,
            }
        finally:
            async with self._lock:
                self._pending_results.pop(request_id, None)

        return {
            "ok": result.get("ok") is True,
            "device_id": connection.device_id,
            "result": result.get("result"),
            "error": result.get("error"),
        }

    async def _select_executor(self, target_device_id: str | None) -> AgentConnection | None:
        async with self._lock:
            if target_device_id:
                return self._connections.get(target_device_id)

            preferred_device = next(
                (
                    device
                    for device in list_registered_devices()
                    if device["connected"]
                    and device["is_active"]
                    and device["preferred_for_desktop_control"]
                    and "desktop.control" in device["capabilities"]
                ),
                None,
            )
            if preferred_device is not None:
                return self._connections.get(preferred_device["device_id"])

            for device_id, connection in self._connections.items():
                device = get_device(device_id)
                if device is None or not device["is_active"]:
                    continue
                if "desktop.control" in connection.capabilities:
                    return connection
        return None


agent_gateway = AgentGateway()
