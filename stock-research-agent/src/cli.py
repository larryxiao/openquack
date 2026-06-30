"""命令行入口。

阶段 0 仅实现：--version、init-db 子命令、以及后续阶段的占位子命令骨架。
随阶段推进，各子命令逐步接到 data/graph/framework/... 各模块。

用法：
    uv run python -m src.cli --version
    uv run python -m src.cli init-db
"""

from __future__ import annotations

import argparse
import sys

from . import __version__

# 后续阶段会接上的子命令 -> 提示文案。阶段 0 先以占位形式登记，
# 让 `--help` 就能看到完整路线图，避免"做到哪了"含糊不清。
_PLANNED = {
    "theme": "阶段 1：展开主题产业链图谱（expander + resolver + quotes）",
    "score": "阶段 2：计算某主题当日入场评分（技术/基本面/情绪）",
    "monitor": "阶段 3：监控持仓核心故事是否失效",
    "portfolio": "阶段 4：打印真实组合 + 当日盈亏（只读）",
    "advise": "阶段 5：综合评分 + 故事状态输出结构化判断",
    "judgment": "阶段 6：模糊判断 → 可证伪子命题",
    "report": "阶段 7：生成日报并同步 Notion",
}


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="stockagent",
        description="主题驱动的股票研究放大器 + 个人决策框架引擎（研究工具，不执行交易）",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"stock-research-agent {__version__}",
    )
    sub = parser.add_subparsers(dest="command", metavar="<command>")

    # 阶段 0 已落地：建库。
    p_init = sub.add_parser("init-db", help="创建/迁移本地 SQLite 库")
    p_init.add_argument("--path", default=None, help="库文件路径（缺省读 STOCKAGENT_DB）")

    # 占位子命令：登记路线图，调用时给出清晰的"未实现"提示。
    for name, desc in _PLANNED.items():
        sub.add_parser(name, help=f"[未实现] {desc}")

    return parser


def _cmd_init_db(args: argparse.Namespace) -> int:
    from .store.db import init_db

    path = init_db(args.path)
    print(f"已初始化数据库：{path}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.command is None:
        parser.print_help()
        return 0

    if args.command == "init-db":
        return _cmd_init_db(args)

    if args.command in _PLANNED:
        print(f"`{args.command}` 尚未实现 —— {_PLANNED[args.command]}", file=sys.stderr)
        return 2

    parser.error(f"未知命令：{args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
