"""阶段 0 验收测试：版本入口 + SQLite schema 建库。"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from src import __version__
from src.cli import main
from src.store import db


def test_version_flag(capsys):
    """`--version` 应退出码 0 并打印版本号。"""
    try:
        main(["--version"])
    except SystemExit as exc:  # argparse version action exits
        assert exc.code == 0
    out = capsys.readouterr().out
    assert __version__ in out


def test_cli_module_version_subprocess():
    """验收点：`python -m src.cli --version` 跑通。"""
    root = Path(__file__).resolve().parents[1]
    result = subprocess.run(
        [sys.executable, "-m", "src.cli", "--version"],
        cwd=root,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert __version__ in result.stdout


def test_init_db_creates_tables(tmp_path):
    """init_db 幂等，且建出全部核心表。"""
    target = tmp_path / "t.db"
    db.init_db(target)
    db.init_db(target)  # 再次调用应不报错（幂等）

    with db.connect(target) as conn:
        names = {
            row["name"]
            for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        }
        version = conn.execute(
            "SELECT value FROM meta WHERE key='schema_version'"
        ).fetchone()["value"]

    expected = {
        "meta", "universe", "theme", "graph_node", "quote", "flow",
        "entry_score", "thesis", "thesis_check", "decision",
    }
    assert expected <= names
    assert version == str(db.SCHEMA_VERSION)


def test_no_command_prints_help():
    """无子命令应打印帮助并返回 0。"""
    assert main([]) == 0
