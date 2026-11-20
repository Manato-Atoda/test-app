"""メール送信。

- outbox モード（既定・開発用）: 実際には送らず mail_outbox に保存し、管理コンソールで本文を確認できる。
- smtp モード: SMTP で送信。履歴には仮パスワードを伏せた本文だけを残す。
"""
from __future__ import annotations

import smtplib
import sqlite3
import ssl
from email.message import EmailMessage
from email.utils import formataddr, make_msgid, parseaddr
from email.header import Header
from typing import Optional

from .config import Config
from .db import now


def send_mail(db: sqlite3.Connection, cfg: Config, *, company_id: Optional[int], to: str, subject: str,
              body: str, redacted_body: Optional[str] = None) -> bool:
    if cfg.mail_mode != "smtp":
        db.execute("INSERT INTO mail_outbox (company_id, to_addr, subject, body, status, created_at)"
                   " VALUES (?, ?, ?, ?, 'outbox', ?)", (company_id, to, subject, body, now()))
        return True

    msg = EmailMessage()
    name, addr = parseaddr(cfg.mail_from)
    msg["From"] = formataddr((str(Header(name, "utf-8")), addr)) if name else addr
    msg["To"] = to
    msg["Subject"] = subject
    msg["Message-ID"] = make_msgid(domain=addr.split("@")[-1] if "@" in addr else None)
    msg.set_content(body, charset="utf-8")
    status, error = "sent", None
    try:
        with smtplib.SMTP(cfg.smtp_host, cfg.smtp_port, timeout=20) as smtp:
            if cfg.smtp_starttls:
                smtp.starttls(context=ssl.create_default_context())
            if cfg.smtp_user:
                smtp.login(cfg.smtp_user, cfg.smtp_password)
            smtp.send_message(msg)
    except (OSError, smtplib.SMTPException) as exc:
        status, error = "failed", str(exc)[:300]
    db.execute("INSERT INTO mail_outbox (company_id, to_addr, subject, body, status, error, created_at)"
               " VALUES (?, ?, ?, ?, ?, ?, ?)",
               (company_id, to, subject, redacted_body if redacted_body is not None else body, status, error, now()))
    return status == "sent"
