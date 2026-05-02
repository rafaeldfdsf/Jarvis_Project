"""Persistencia de utilizadores, sessoes e codigos de autenticacao por email."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import base64
import hashlib
import hmac
import secrets
import string

from db_utils import connect


PASSWORD_ITERATIONS = 200_000
SESSION_DURATION_DAYS = 30
EMAIL_CODE_DURATION_MINUTES = 15


@dataclass(frozen=True)
class AuthUser:
    id: str
    email: str
    display_name: str
    created_at: str
    email_verified_at: str | None = None

    @property
    def email_verified(self) -> bool:
        return bool((self.email_verified_at or "").strip())


@dataclass(frozen=True)
class AuthSession:
    token: str
    user_id: str
    created_at: str
    expires_at: str


@dataclass(frozen=True)
class AuthEmailCode:
    id: str
    user_id: str
    email: str
    purpose: str
    code: str
    created_at: str
    expires_at: str


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _utc_now_iso() -> str:
    return _utc_now().isoformat()


def _normalize_email(value: str) -> str:
    return (value or "").strip().lower()


def _normalize_display_name(value: str) -> str:
    return (value or "").strip()


def _normalize_password(value: str) -> str:
    return (value or "").strip()


def _normalize_code(value: str) -> str:
    return "".join(character for character in (value or "").strip() if character.isdigit())


def _hash_password(password: str) -> str:
    clean_password = _normalize_password(password)
    if len(clean_password) < 6:
        raise ValueError("A palavra-passe tem de ter pelo menos 6 caracteres.")

    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        clean_password.encode("utf-8"),
        salt,
        PASSWORD_ITERATIONS,
    )
    return (
        f"pbkdf2_sha256${PASSWORD_ITERATIONS}$"
        f"{base64.b64encode(salt).decode('ascii')}$"
        f"{base64.b64encode(digest).decode('ascii')}"
    )


def _verify_password(password: str, encoded_hash: str) -> bool:
    try:
        algorithm, raw_iterations, raw_salt, raw_digest = encoded_hash.split("$", 3)
    except ValueError:
        return False

    if algorithm != "pbkdf2_sha256":
        return False

    try:
        iterations = int(raw_iterations)
        salt = base64.b64decode(raw_salt.encode("ascii"))
        digest = base64.b64decode(raw_digest.encode("ascii"))
    except Exception:
        return False

    candidate = hashlib.pbkdf2_hmac(
        "sha256",
        _normalize_password(password).encode("utf-8"),
        salt,
        iterations,
    )
    return hmac.compare_digest(candidate, digest)


def _hash_email_code(code: str) -> str:
    return hashlib.sha256(_normalize_code(code).encode("utf-8")).hexdigest()


def _generate_email_code() -> str:
    digits = string.digits
    return "".join(secrets.choice(digits) for _ in range(6))


def _row_to_user(row) -> AuthUser:
    return AuthUser(
        id=row["id"],
        email=row["email"],
        display_name=row["display_name"],
        created_at=row["created_at"],
        email_verified_at=row["email_verified_at"],
    )


def _row_to_session(row) -> AuthSession:
    return AuthSession(
        token=row["token"],
        user_id=row["user_id"],
        created_at=row["created_at"],
        expires_at=row["expires_at"],
    )


def _ensure_column(cursor, table_name: str, column_name: str, definition: str) -> None:
    cursor.execute(f"PRAGMA table_info({table_name})")
    columns = {row["name"] for row in cursor.fetchall()}
    if column_name not in columns:
        cursor.execute(f"ALTER TABLE {table_name} ADD COLUMN {column_name} {definition}")


def init_auth_db() -> None:
    conn = connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            email TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            display_name TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            email_verified_at TEXT
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS auth_sessions (
            token TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            expires_at TEXT NOT NULL
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS auth_email_codes (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            email TEXT NOT NULL,
            purpose TEXT NOT NULL,
            code_hash TEXT NOT NULL,
            created_at TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            consumed_at TEXT,
            UNIQUE(email, purpose, id)
        )
        """
    )
    _ensure_column(cursor, "users", "email_verified_at", "TEXT")
    conn.commit()
    conn.close()


def count_users() -> int:
    init_auth_db()
    conn = connect()
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) AS total FROM users")
    row = cursor.fetchone()
    conn.close()
    return int(row["total"] or 0)


def create_user(*, email: str, password: str, display_name: str = "") -> AuthUser:
    init_auth_db()
    clean_email = _normalize_email(email)
    clean_display_name = _normalize_display_name(display_name)
    if "@" not in clean_email or "." not in clean_email.split("@", 1)[-1]:
        raise ValueError("Email invalido.")

    now = _utc_now_iso()
    user_id = secrets.token_hex(16)
    password_hash = _hash_password(password)

    conn = connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        SELECT id, email_verified_at
        FROM users
        WHERE email = ?
        """,
        (clean_email,),
    )
    existing = cursor.fetchone()
    if existing is not None:
        conn.close()
        raise ValueError("Ja existe uma conta com esse email.")

    cursor.execute(
        """
        INSERT INTO users (id, email, password_hash, display_name, created_at, email_verified_at)
        VALUES (?, ?, ?, ?, ?, NULL)
        """,
        (
            user_id,
            clean_email,
            password_hash,
            clean_display_name,
            now,
        ),
    )
    conn.commit()
    cursor.execute(
        """
        SELECT id, email, display_name, created_at, email_verified_at
        FROM users
        WHERE id = ?
        """,
        (user_id,),
    )
    row = cursor.fetchone()
    conn.close()
    return _row_to_user(row)


def get_user_by_email(email: str) -> AuthUser | None:
    init_auth_db()
    conn = connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        SELECT id, email, display_name, created_at, email_verified_at
        FROM users
        WHERE email = ?
        """,
        (_normalize_email(email),),
    )
    row = cursor.fetchone()
    conn.close()
    return _row_to_user(row) if row else None


def get_user_by_id(user_id: str) -> AuthUser | None:
    init_auth_db()
    conn = connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        SELECT id, email, display_name, created_at, email_verified_at
        FROM users
        WHERE id = ?
        """,
        ((user_id or "").strip(),),
    )
    row = cursor.fetchone()
    conn.close()
    return _row_to_user(row) if row else None


def authenticate_user(email: str, password: str) -> AuthUser | None:
    init_auth_db()
    conn = connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        SELECT id, email, password_hash, display_name, created_at, email_verified_at
        FROM users
        WHERE email = ?
        """,
        (_normalize_email(email),),
    )
    row = cursor.fetchone()
    conn.close()
    if row is None:
        return None
    if not _verify_password(password, row["password_hash"]):
        return None
    return AuthUser(
        id=row["id"],
        email=row["email"],
        display_name=row["display_name"],
        created_at=row["created_at"],
        email_verified_at=row["email_verified_at"],
    )


def create_auth_session(user_id: str) -> AuthSession:
    init_auth_db()
    now = _utc_now()
    session = AuthSession(
        token=secrets.token_urlsafe(32),
        user_id=(user_id or "").strip(),
        created_at=now.isoformat(),
        expires_at=(now + timedelta(days=SESSION_DURATION_DAYS)).isoformat(),
    )

    conn = connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        INSERT INTO auth_sessions (token, user_id, created_at, expires_at)
        VALUES (?, ?, ?, ?)
        """,
        (
            session.token,
            session.user_id,
            session.created_at,
            session.expires_at,
        ),
    )
    conn.commit()
    conn.close()
    return session


def revoke_auth_session(token: str) -> bool:
    init_auth_db()
    conn = connect()
    cursor = conn.cursor()
    cursor.execute(
        "DELETE FROM auth_sessions WHERE token = ?",
        ((token or "").strip(),),
    )
    deleted = cursor.rowcount > 0
    conn.commit()
    conn.close()
    return deleted


def revoke_user_sessions(user_id: str) -> int:
    init_auth_db()
    clean_user_id = (user_id or "").strip()
    if not clean_user_id:
        return 0

    conn = connect()
    cursor = conn.cursor()
    cursor.execute(
        "DELETE FROM auth_sessions WHERE user_id = ?",
        (clean_user_id,),
    )
    deleted = cursor.rowcount or 0
    conn.commit()
    conn.close()
    return int(deleted)


def resolve_auth_session(token: str) -> tuple[AuthSession, AuthUser] | None:
    init_auth_db()
    clean_token = (token or "").strip()
    if not clean_token:
        return None

    conn = connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        SELECT s.token, s.user_id, s.created_at, s.expires_at,
               u.id, u.email, u.display_name, u.created_at AS user_created_at,
               u.email_verified_at
        FROM auth_sessions s
        JOIN users u ON u.id = s.user_id
        WHERE s.token = ?
        """,
        (clean_token,),
    )
    row = cursor.fetchone()
    if row is None:
        conn.close()
        return None

    expires_at = datetime.fromisoformat(row["expires_at"])
    if expires_at <= _utc_now():
        cursor.execute("DELETE FROM auth_sessions WHERE token = ?", (clean_token,))
        conn.commit()
        conn.close()
        return None

    session = AuthSession(
        token=row["token"],
        user_id=row["user_id"],
        created_at=row["created_at"],
        expires_at=row["expires_at"],
    )
    user = AuthUser(
        id=row["id"],
        email=row["email"],
        display_name=row["display_name"],
        created_at=row["user_created_at"],
        email_verified_at=row["email_verified_at"],
    )
    conn.close()
    return session, user


def create_email_code(*, user_id: str, email: str, purpose: str) -> AuthEmailCode:
    init_auth_db()
    code = _generate_email_code()
    now = _utc_now()
    record = AuthEmailCode(
        id=secrets.token_hex(16),
        user_id=(user_id or "").strip(),
        email=_normalize_email(email),
        purpose=(purpose or "").strip().lower(),
        code=code,
        created_at=now.isoformat(),
        expires_at=(now + timedelta(minutes=EMAIL_CODE_DURATION_MINUTES)).isoformat(),
    )

    conn = connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        UPDATE auth_email_codes
        SET consumed_at = ?
        WHERE email = ? AND purpose = ? AND consumed_at IS NULL
        """,
        (
            record.created_at,
            record.email,
            record.purpose,
        ),
    )
    cursor.execute(
        """
        INSERT INTO auth_email_codes (
            id, user_id, email, purpose, code_hash, created_at, expires_at, consumed_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, NULL)
        """,
        (
            record.id,
            record.user_id,
            record.email,
            record.purpose,
            _hash_email_code(record.code),
            record.created_at,
            record.expires_at,
        ),
    )
    conn.commit()
    conn.close()
    return record


def consume_email_code(*, email: str, purpose: str, code: str) -> AuthUser | None:
    init_auth_db()
    clean_email = _normalize_email(email)
    clean_purpose = (purpose or "").strip().lower()
    clean_code = _normalize_code(code)
    if not clean_email or not clean_purpose or not clean_code:
        return None

    conn = connect()
    cursor = conn.cursor()
    cursor.execute(
        """
        SELECT c.id, c.user_id, c.code_hash, c.expires_at, c.consumed_at,
               u.id AS auth_user_id, u.email, u.display_name, u.created_at, u.email_verified_at
        FROM auth_email_codes c
        JOIN users u ON u.id = c.user_id
        WHERE c.email = ? AND c.purpose = ?
        ORDER BY c.created_at DESC
        LIMIT 1
        """,
        (
            clean_email,
            clean_purpose,
        ),
    )
    row = cursor.fetchone()
    if row is None:
        conn.close()
        return None

    if row["consumed_at"]:
        conn.close()
        return None

    expires_at = datetime.fromisoformat(row["expires_at"])
    if expires_at <= _utc_now():
        conn.close()
        return None

    if not hmac.compare_digest(row["code_hash"], _hash_email_code(clean_code)):
        conn.close()
        return None

    consumed_at = _utc_now_iso()
    cursor.execute(
        "UPDATE auth_email_codes SET consumed_at = ? WHERE id = ?",
        (consumed_at, row["id"]),
    )
    conn.commit()
    user = AuthUser(
        id=row["auth_user_id"],
        email=row["email"],
        display_name=row["display_name"],
        created_at=row["created_at"],
        email_verified_at=row["email_verified_at"],
    )
    conn.close()
    return user


def mark_user_email_verified(user_id: str) -> AuthUser | None:
    init_auth_db()
    clean_user_id = (user_id or "").strip()
    if not clean_user_id:
        return None

    conn = connect()
    cursor = conn.cursor()
    verified_at = _utc_now_iso()
    cursor.execute(
        "UPDATE users SET email_verified_at = ? WHERE id = ?",
        (
            verified_at,
            clean_user_id,
        ),
    )
    if cursor.rowcount <= 0:
        conn.commit()
        conn.close()
        return None

    conn.commit()
    cursor.execute(
        """
        SELECT id, email, display_name, created_at, email_verified_at
        FROM users
        WHERE id = ?
        """,
        (clean_user_id,),
    )
    row = cursor.fetchone()
    conn.close()
    return _row_to_user(row) if row else None


def update_user_password(user_id: str, new_password: str) -> AuthUser | None:
    init_auth_db()
    clean_user_id = (user_id or "").strip()
    if not clean_user_id:
        return None

    password_hash = _hash_password(new_password)
    conn = connect()
    cursor = conn.cursor()
    cursor.execute(
        "UPDATE users SET password_hash = ? WHERE id = ?",
        (
            password_hash,
            clean_user_id,
        ),
    )
    if cursor.rowcount <= 0:
        conn.commit()
        conn.close()
        return None

    conn.commit()
    cursor.execute(
        """
        SELECT id, email, display_name, created_at, email_verified_at
        FROM users
        WHERE id = ?
        """,
        (clean_user_id,),
    )
    row = cursor.fetchone()
    conn.close()
    return _row_to_user(row) if row else None
