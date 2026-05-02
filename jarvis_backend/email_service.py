"""Envio simples de emails transacionais por SMTP."""

from __future__ import annotations

from email.message import EmailMessage
import smtplib

from config import settings


def is_email_enabled() -> bool:
    return settings.smtp_enabled


def _build_message(*, to_email: str, subject: str, body: str) -> EmailMessage:
    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = (
        f"{settings.smtp_from_name} <{settings.smtp_from_email}>"
        if settings.smtp_from_name.strip()
        else settings.smtp_from_email
    )
    message["To"] = to_email.strip()
    message.set_content(body)
    return message


def send_email(*, to_email: str, subject: str, body: str) -> None:
    if not settings.smtp_enabled:
        raise RuntimeError(
            "O envio de emails nao esta configurado. Define JARVIS_SMTP_HOST, "
            "JARVIS_SMTP_PORT e JARVIS_SMTP_FROM_EMAIL."
        )

    message = _build_message(to_email=to_email, subject=subject, body=body)

    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=20) as smtp:
        smtp.ehlo()
        if settings.smtp_use_tls:
            smtp.starttls()
            smtp.ehlo()
        if settings.smtp_username:
            smtp.login(settings.smtp_username, settings.smtp_password)
        smtp.send_message(message)


def send_registration_email(*, to_email: str, display_name: str, code: str) -> None:
    subject = f"{settings.app_name}: confirma a tua conta"
    body = (
        f"Ola {display_name or 'utilizador'},\n\n"
        f"Recebemos um pedido para criar uma conta no {settings.app_name}.\n"
        f"Usa este codigo para confirmar o teu email na aplicacao:\n\n"
        f"{code}\n\n"
        "Se nao foste tu, podes ignorar este email.\n"
    )
    send_email(to_email=to_email, subject=subject, body=body)


def send_password_reset_email(*, to_email: str, display_name: str, code: str) -> None:
    subject = f"{settings.app_name}: recuperacao de palavra-passe"
    body = (
        f"Ola {display_name or 'utilizador'},\n\n"
        f"Recebemos um pedido para repor a palavra-passe da tua conta no {settings.app_name}.\n"
        f"Usa este codigo na aplicacao para definir uma nova palavra-passe:\n\n"
        f"{code}\n\n"
        "Se nao foste tu, podes ignorar este email.\n"
    )
    send_email(to_email=to_email, subject=subject, body=body)
