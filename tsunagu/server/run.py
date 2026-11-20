"""起動用スクリプト（どこからでも実行できる）: python3 tsunagu/server/run.py serve --seed-demo"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from tsunagu_server.__main__ import main  # noqa: E402

sys.exit(main())
