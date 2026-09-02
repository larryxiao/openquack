"""SQLite schema + 读写基础设施。

阶段 0 只负责：定义 schema、建库、提供连接句柄。后续阶段在此之上
增加各表的读写 helper。所有持仓相关数据只读缓存，不写回任何券商。
"""

from __future__ import annotations

import os
import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

# 缺省库路径：项目根目录下 data/stockagent.db，可用环境变量覆盖。
DEFAULT_DB_PATH = "data/stockagent.db"

SCHEMA_VERSION = 1

# --- schema 定义 ---------------------------------------------------------
# 设计原则（见 PROJECT_PLAN.md 第 4 节）：
#   - LLM 只报公司名，代码由 resolver 校验后落入 universe / graph_node。
#   - 代码算确定性指标（quote），LLM 做叙事解读。
#   - 出场基于"故事失效"，故 thesis / thesis_check 是一等公民。

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT
);

-- 全市场标的表（akshare 缓存，阶段 1）。resolver 防幻觉的事实源。
CREATE TABLE IF NOT EXISTS universe (
    code        TEXT NOT NULL,          -- A股 6 位 / 港股 / 美股 ticker
    market      TEXT NOT NULL,          -- cn / hk / us
    name        TEXT NOT NULL,
    pinyin      TEXT,                   -- 名称模糊匹配辅助
    updated_at  TEXT NOT NULL,
    PRIMARY KEY (market, code)
);
CREATE INDEX IF NOT EXISTS idx_universe_name ON universe(name);

-- 主题产业链图谱（阶段 1，expander 输出 + resolver 校验后落库）。
CREATE TABLE IF NOT EXISTS theme (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL UNIQUE,
    core_thesis TEXT,
    expanded_at TEXT
);
CREATE TABLE IF NOT EXISTS graph_node (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    theme_id    INTEGER NOT NULL REFERENCES theme(id),
    layer       TEXT NOT NULL,          -- 总装 / 分系统 / 上游材料 ...
    company     TEXT NOT NULL,          -- LLM 给出的公司名
    market      TEXT,                   -- resolver 校验后填入
    code        TEXT,                   -- resolver 校验后填入；NULL=未确认
    resolved    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_node_theme ON graph_node(theme_id);

-- 行情缓存（阶段 1，quotes 层；带重试/降级，落库做快照）。
CREATE TABLE IF NOT EXISTS quote (
    market      TEXT NOT NULL,
    code        TEXT NOT NULL,
    asof        TEXT NOT NULL,          -- 交易日 / 时间戳
    last        REAL,
    pct_change  REAL,
    volume      REAL,
    market_cap  REAL,
    PRIMARY KEY (market, code, asof)
);

-- 北向资金 / 板块轮动（阶段 3，flows 层）。
CREATE TABLE IF NOT EXISTS flow (
    asof        TEXT NOT NULL,
    kind        TEXT NOT NULL,          -- northbound / sector_rotation ...
    label       TEXT NOT NULL,          -- 板块名 / 渠道
    value       REAL,                   -- 净额（亿）等
    PRIMARY KEY (asof, kind, label)
);

-- 入场框架打分（阶段 2，entry 层）。三维：technical/fundamental/sentiment。
CREATE TABLE IF NOT EXISTS entry_score (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    theme       TEXT NOT NULL,
    asof        TEXT NOT NULL,
    total       INTEGER,
    technical   INTEGER,
    fundamental INTEGER,
    sentiment   INTEGER,
    detail      TEXT                    -- JSON：各维归因
);
CREATE INDEX IF NOT EXISTS idx_score_theme ON entry_score(theme, asof);

-- 持仓核心故事（阶段 2/3，thesis 层）：为什么进场。
CREATE TABLE IF NOT EXISTS thesis (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    theme       TEXT,
    market      TEXT,
    code        TEXT,
    story       TEXT NOT NULL,          -- 核心故事
    created_at  TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'active'  -- active / closed / invalidated
);

-- 故事可证伪子命题 + 监控结果（阶段 3/6）。
CREATE TABLE IF NOT EXISTS thesis_check (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    thesis_id   INTEGER NOT NULL REFERENCES thesis(id),
    asof        TEXT NOT NULL,
    claim       TEXT NOT NULL,          -- 可观测子命题
    metric      TEXT,                   -- 映射到的指标（订单/库存/北向/财报）
    signal      TEXT,                   -- support / neutral / falsify
    note        TEXT
);
CREATE INDEX IF NOT EXISTS idx_check_thesis ON thesis_check(thesis_id, asof);

-- 结构化决策记录（阶段 5，advisor 输出，沉淀到 Notion 前的本地源）。
CREATE TABLE IF NOT EXISTS decision (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    asof        TEXT NOT NULL,
    theme       TEXT,
    verdict     TEXT,                   -- 结构化判断文本
    payload     TEXT                    -- JSON：评分 + 故事状态快照
);
"""


def db_path() -> Path:
    """解析库文件路径，优先环境变量 STOCKAGENT_DB。"""
    raw = os.environ.get("STOCKAGENT_DB", DEFAULT_DB_PATH)
    return Path(raw).expanduser()


def connect(path: str | os.PathLike[str] | None = None) -> sqlite3.Connection:
    """打开（必要时创建）数据库连接，启用外键与 Row 工厂。"""
    target = Path(path) if path is not None else db_path()
    target.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(target)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON;")
    return conn


def init_db(path: str | os.PathLike[str] | None = None) -> Path:
    """建库并应用 schema（幂等）。返回库文件路径。"""
    target = Path(path) if path is not None else db_path()
    with connect(target) as conn:
        conn.executescript(SCHEMA_SQL)
        conn.execute(
            "INSERT INTO meta(key, value) VALUES('schema_version', ?) "
            "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (str(SCHEMA_VERSION),),
        )
        conn.commit()
    return target


@contextmanager
def session(path: str | os.PathLike[str] | None = None) -> Iterator[sqlite3.Connection]:
    """上下文管理：进入即建库，提交/回滚自动处理。"""
    conn = connect(path)
    try:
        conn.executescript(SCHEMA_SQL)
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
