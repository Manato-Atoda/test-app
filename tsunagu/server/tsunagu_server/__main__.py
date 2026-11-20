"""コマンドライン:

  python3 -m tsunagu_server serve [--host 127.0.0.1] [--port 8790] [--seed-demo]
  python3 -m tsunagu_server create-company --code ACME --name "株式会社エーシーエムイー" \\
      --admin-code A0001 --admin-name "山田 太郎" [--admin-email ...] [--pdf 出力先.pdf]
  python3 -m tsunagu_server reset-password --company ACME --user A0001 [--pdf 出力先.pdf]
  python3 -m tsunagu_server seed-demo
"""
from __future__ import annotations

import argparse
import os
import sys

from .app import serve
from .config import load_config
from .db import connect, init_db
from .operator_tools import create_company, reissue_credentials, seed_demo
from .pdf import build_account_notices_pdf
from .web import ApiError


def main(argv: list = None) -> int:
    parser = argparse.ArgumentParser(prog="tsunagu_server", description="社内SNS「M」サーバー")
    sub = parser.add_subparsers(dest="command", required=True)

    p_serve = sub.add_parser("serve", help="サーバーを起動")
    p_serve.add_argument("--host", default="127.0.0.1")
    p_serve.add_argument("--port", type=int, default=8790)
    p_serve.add_argument("--seed-demo", action="store_true", help="デモ企業がなければ作ってから起動（開発用）")
    p_serve.add_argument("--db", help="データベースのファイル（既定: server/var/tsunagu.db）")

    p_company = sub.add_parser("create-company", help="企業と最初の管理者を作成（運営者用）")
    p_company.add_argument("--code", required=True, help="企業コード（半角英数字3〜16文字）")
    p_company.add_argument("--name", required=True, help="企業名")
    p_company.add_argument("--admin-code", required=True, help="管理者の社員コード")
    p_company.add_argument("--admin-name", required=True, help="管理者の氏名")
    p_company.add_argument("--admin-email", default="", help="管理者のメールアドレス")
    p_company.add_argument("--admin-department", default="")
    p_company.add_argument("--pdf", help="管理者のアカウント発行通知書（PDF）の出力先")

    p_reset = sub.add_parser("reset-password",
                             help="社員の仮パスワードを再発行（管理者がログインできなくなったときの運営者用）")
    p_reset.add_argument("--company", required=True, help="企業コード")
    p_reset.add_argument("--user", required=True, help="社員コード または メールアドレス")
    p_reset.add_argument("--pdf", help="アカウント発行通知書（PDF）の出力先")
    p_reset.add_argument("--db", help="データベースのファイル（既定: server/var/tsunagu.db）")

    sub.add_parser("seed-demo", help="デモ企業（DEMO）を作成（開発用）")

    args = parser.parse_args(argv)
    cfg = load_config()
    if getattr(args, "db", None):
        cfg.db_path = os.path.abspath(args.db)
    init_db(cfg.db_path)

    if args.command == "serve":
        if args.seed_demo:
            _seed(cfg)
        serve(cfg, args.host, args.port)
        return 0

    if args.command == "seed-demo":
        _seed(cfg)
        return 0

    if args.command == "reset-password":
        db = connect(cfg.db_path)
        try:
            notice = reissue_credentials(db, cfg, company_code=args.company, login_id=args.user)
            out = args.pdf or os.path.join(os.path.dirname(cfg.db_path),
                                           "%s-%s-notice.pdf" % (notice.company_code, notice.employee_code))
            _write_pdf(out, notice)
            db.commit()
        except ApiError as err:
            db.rollback()
            print("エラー: " + err.message, file=sys.stderr)
            return 1
        finally:
            db.close()
        print("%s さん（%s / %s）の仮パスワードを再発行しました。今のパスワードは使えなくなり、全端末からログアウトしました。"
              % (notice.display_name, notice.company_code, notice.employee_code))
        print("アカウント発行通知書: %s" % out)
        print("この PDF には仮パスワードが入っています。本人に渡したら削除してください。")
        return 0

    db = connect(cfg.db_path)
    try:
        _, _, notice = create_company(db, cfg, code=args.code, name=args.name, admin={
            "employee_code": args.admin_code, "display_name": args.admin_name, "email": args.admin_email,
            "department": args.admin_department})
        out = args.pdf or os.path.join(os.path.dirname(cfg.db_path), "%s-admin-notice.pdf" % notice.company_code)
        _write_pdf(out, notice)
        db.commit()
    except ApiError as err:
        db.rollback()
        print("エラー: " + err.message, file=sys.stderr)
        return 1
    finally:
        db.close()
    print("企業 %s（%s）を作成しました。" % (notice.company_name, notice.company_code))
    print("管理者 %s のアカウント発行通知書: %s" % (notice.display_name, out))
    print("この PDF には仮パスワードが入っています。管理者本人に渡したら削除してください。")
    return 0


def _write_pdf(path: str, notice) -> None:
    """通知書を本人だけが読める権限（600）で書き出す。"""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as fh:
        fh.write(build_account_notices_pdf([notice]))


def _seed(cfg) -> None:
    db = connect(cfg.db_path)
    try:
        created = seed_demo(db, cfg)
        db.commit()
    finally:
        db.close()
    if created:
        print("デモ企業（企業コード DEMO）を作成しました。仮パスワードは operator_tools.py の DEMO_TEMP_PASSWORD です。")
    else:
        print("デモ企業は既にあります。")


if __name__ == "__main__":
    sys.exit(main())
