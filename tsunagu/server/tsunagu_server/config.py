"""設定（環境変数で上書きできる）。"""
from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import List
from urllib.parse import urlparse

SERVER_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


@dataclass
class Config:
    db_path: str = os.path.join(SERVER_DIR, "var", "tsunagu.db")
    public_url: str = "http://localhost:8790"
    rp_id: str = ""
    rp_name: str = "M"
    allowed_origins: List[str] = field(default_factory=list)
    app_scheme: str = "tsunagu"
    # outbox: 送らずに DB に保存して管理コンソールで確認（開発用） / smtp: 実際に送信
    mail_mode: str = "outbox"
    mail_from: str = "M <no-reply@example.com>"
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_starttls: bool = True
    trust_proxy: bool = False  # リバースプロキシ配下なら X-Forwarded-For を使う

    def __post_init__(self) -> None:
        self.public_url = self.public_url.rstrip("/")
        parsed = urlparse(self.public_url)
        if not self.rp_id:
            self.rp_id = parsed.hostname or "localhost"
        if not self.allowed_origins:
            self.allowed_origins = ["%s://%s" % (parsed.scheme, parsed.netloc)]

    @property
    def is_dev_mail(self) -> bool:
        return self.mail_mode != "smtp"


def load_config() -> Config:
    env = os.environ.get
    kwargs = {}
    if env("TSUNAGU_DB"):
        kwargs["db_path"] = env("TSUNAGU_DB")
    if env("TSUNAGU_PUBLIC_URL"):
        kwargs["public_url"] = env("TSUNAGU_PUBLIC_URL")
    if env("TSUNAGU_RP_ID"):
        kwargs["rp_id"] = env("TSUNAGU_RP_ID")
    if env("TSUNAGU_ORIGINS"):
        kwargs["allowed_origins"] = [o.strip() for o in env("TSUNAGU_ORIGINS", "").split(",") if o.strip()]
    if env("TSUNAGU_APP_SCHEME"):
        kwargs["app_scheme"] = env("TSUNAGU_APP_SCHEME")
    if env("TSUNAGU_MAIL_MODE"):
        kwargs["mail_mode"] = env("TSUNAGU_MAIL_MODE")
    if env("TSUNAGU_MAIL_FROM"):
        kwargs["mail_from"] = env("TSUNAGU_MAIL_FROM")
    if env("TSUNAGU_SMTP_HOST"):
        kwargs["smtp_host"] = env("TSUNAGU_SMTP_HOST")
    if env("TSUNAGU_SMTP_PORT"):
        kwargs["smtp_port"] = int(env("TSUNAGU_SMTP_PORT", "587"))
    if env("TSUNAGU_SMTP_USER"):
        kwargs["smtp_user"] = env("TSUNAGU_SMTP_USER")
    if env("TSUNAGU_SMTP_PASSWORD"):
        kwargs["smtp_password"] = env("TSUNAGU_SMTP_PASSWORD")
    if env("TSUNAGU_SMTP_STARTTLS"):
        kwargs["smtp_starttls"] = env("TSUNAGU_SMTP_STARTTLS") not in ("0", "false", "no")
    if env("TSUNAGU_TRUST_PROXY"):
        kwargs["trust_proxy"] = env("TSUNAGU_TRUST_PROXY") in ("1", "true", "yes")
    return Config(**kwargs)
