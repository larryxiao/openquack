# stock-research-agent

主题驱动的股票研究放大器 + 个人决策框架引擎。

> 完整设计见 [`PROJECT_PLAN.md`](./PROJECT_PLAN.md)。

## 边界（硬约束）

- 本系统是**研究与信息整理工具**，持仓数据**只读**。
- **不执行任何交易/转账操作。**
- **不提供个性化买卖建议**。所有打分/信号/框架评估都是辅助判断的
  结构化信息，最终决策与下单始终由使用者手动完成。

## 快速开始

```bash
cd stock-research-agent
uv sync                       # 安装基础依赖
cp .env.example .env          # 填入 API key 等

uv run python -m src.cli --version
uv run python -m src.cli init-db
uv run python -m src.cli --help
```

## 进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| 0 | 地基：uv 骨架 / .env / SQLite schema / cli 入口 | ✅ 已完成 |
| 1 | 产业链图谱引擎（universe / expander / resolver / quotes） | ⏳ |
| 2 | 入场框架引擎（三维打分 / thesis / frameworks） | ⏳ |
| 3 | 故事监控层（thesis_validator / flows） | ⏳ |
| 4 | 真实持仓接入（futu / ibkr，只读） | ⏳ |
| 5 | 决策建议生成（advisor / exit） | ⏳ |
| 6 | 直觉迭代层（judgment / Notion 观点库） | ⏳ |
| 7 | 日报 + launchd 调度 | ⏳ |

## 开发

```bash
uv run pytest          # 运行测试
```
