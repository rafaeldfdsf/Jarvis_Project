"""Integracao com a API REST do Home Assistant."""

from __future__ import annotations

from typing import Any

import requests

from config import settings
from home_assistant.devices import resolve_device_reference
from memory.user_memory import load_facts


def _is_enabled(user_id: str | None = None) -> bool:
    facts = load_facts(user_id=user_id)
    raw = str(facts.get("home_assistant_enabled") or "").strip().lower()
    if raw:
        return raw in {"1", "true", "yes", "on"}
    url = str(facts.get("home_assistant_url") or "").strip()
    token = str(facts.get("home_assistant_token") or "").strip()
    return bool(url and token)


def _base_url(user_id: str | None = None) -> str:
    if not _is_enabled(user_id=user_id):
        raise ValueError("Home Assistant desativado nas configuracoes.")
    facts = load_facts(user_id=user_id)
    url = (facts.get("home_assistant_url") or "").strip().rstrip("/")
    if not url:
        raise ValueError("URL do Home Assistant nao configurada.")
    return url


def _token(user_id: str | None = None) -> str:
    if not _is_enabled(user_id=user_id):
        raise ValueError("Home Assistant desativado nas configuracoes.")
    facts = load_facts(user_id=user_id)
    token = (facts.get("home_assistant_token") or "").strip()
    if not token:
        raise ValueError("Token do Home Assistant nao configurado.")
    return token


def _headers(user_id: str | None = None) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {_token(user_id=user_id)}",
        "Content-Type": "application/json",
    }


def _request(method: str, path: str, *, json_payload: Any | None = None, user_id: str | None = None) -> Any:
    response = requests.request(
        method=method,
        url=f"{_base_url(user_id=user_id)}{path}",
        headers=_headers(user_id=user_id),
        json=json_payload,
        timeout=settings.weather_timeout_seconds,
    )
    response.raise_for_status()
    if not response.content:
        return None
    return response.json()


def connection_status(user_id: str | None = None) -> dict[str, Any]:
    facts = load_facts(user_id=user_id)
    enabled = _is_enabled(user_id=user_id)
    url = (facts.get("home_assistant_url") or "").strip().rstrip("/")
    token = (facts.get("home_assistant_token") or "").strip()

    if not enabled:
        return {
            "enabled": False,
            "configured": bool(url and token),
            "connected": False,
            "url": url,
            "message": "Home Assistant desativado nas configuracoes.",
        }

    if not url or not token:
        return {
            "enabled": True,
            "configured": False,
            "connected": False,
            "url": url,
            "message": "Configura URL e token do Home Assistant.",
        }

    try:
        config = _request("GET", "/api/config", user_id=user_id)
        states = _request("GET", "/api/states", user_id=user_id)
        return {
            "enabled": True,
            "configured": True,
            "connected": True,
            "url": url,
            "location_name": config.get("location_name"),
            "entity_count": len(states) if isinstance(states, list) else 0,
            "message": "Ligacao ao Home Assistant ativa.",
        }
    except Exception as exc:
        return {
            "enabled": True,
            "configured": True,
            "connected": False,
            "url": url,
            "message": str(exc),
        }


def list_entities(domain: str | None = None, user_id: str | None = None) -> list[dict[str, Any]]:
    states = _request("GET", "/api/states", user_id=user_id)
    if not isinstance(states, list):
        return []

    selected_domain = (domain or "").strip().lower()
    entities = []

    for item in states:
        entity_id = str(item.get("entity_id") or "").strip()
        entity_domain = entity_id.split(".", 1)[0] if "." in entity_id else ""
        if selected_domain and entity_domain != selected_domain:
            continue

        attributes = item.get("attributes") or {}
        entities.append(
            {
                "entity_id": entity_id,
                "domain": entity_domain,
                "state": item.get("state"),
                "friendly_name": attributes.get("friendly_name") or entity_id,
                "attributes": attributes,
            }
        )

    entities.sort(key=lambda entry: (entry["domain"], entry["friendly_name"].lower()))
    return entities


def call_service(
    domain: str,
    service: str,
    *,
    entity_id: str | None = None,
    service_data: dict[str, Any] | None = None,
    user_id: str | None = None,
) -> dict[str, Any]:
    clean_domain = (domain or "").strip().lower()
    clean_service = (service or "").strip().lower()

    if not clean_domain or not clean_service:
        raise ValueError("Domain e service do Home Assistant sao obrigatorios.")

    payload = dict(service_data or {})
    resolved_device = None
    requested_entity_id = (entity_id or "").strip()
    if requested_entity_id:
        resolved_device = resolve_device_reference(
            requested_entity_id,
            domain=clean_domain,
            user_id=user_id,
        )
        if "entity_id" not in payload:
            payload["entity_id"] = (
                resolved_device["entity_id"]
                if resolved_device is not None
                else requested_entity_id
            )

    result = _request(
        "POST",
        f"/api/services/{clean_domain}/{clean_service}",
        json_payload=payload,
        user_id=user_id,
    )

    return {
        "domain": clean_domain,
        "service": clean_service,
        "entity_id": payload.get("entity_id"),
        "resolved_from": requested_entity_id or None,
        "resolved_alias": (
            str(resolved_device.get("alias") or "").strip() if resolved_device else None
        ),
        "result": result,
    }
