# Contexta Server

Contexta 英语学习 App 的服务端（Rust）：DeepSeek API key 只存服务端，提供查词兜底（含配额/缓存/用量账本）与每日文章生成 + 管理员审核 + App 每日同步。单二进制部署（含 Vue3 管理页）。

## 快速启动

```bash
cd impl/server

# 必填：JWT_SECRET（>=32 字符）与 DEEPSEEK_API_KEY，缺失启动失败
export JWT_SECRET=$(openssl rand -hex 32)
export DEEPSEEK_API_KEY=<your-key>

# 可选（有默认值）：PORT / DB_PATH / WORD_QUOTA_DAILY / ARTICLE_BUDGET_DAILY /
# DAILY_GENERATE_HOUR / LLM_TIMEOUT_SECS / DEEPSEEK_MODEL / DEEPSEEK_BASE_URL /
# CACHE_TTL_DAYS / CACHE_MAX_ROWS / ADMIN_INIT_PASSWORD（首次启动设此值即 seed 管理员 admin）

cargo run
```

启动后：
- 健康检查：`GET http://localhost:8080/api/health`
- 管理页：`http://localhost:8080/admin`（首次启动前设 `ADMIN_INIT_PASSWORD` 以 seed 管理员 `admin`）

详细配置与部署（云主机选型 / Caddy HTTPS / systemd / 备份 / 首次启动顺序 / 已裁决语义）见 [docs/config-and-deploy.md](docs/config-and-deploy.md)，架构见 [docs/architecture.md](docs/architecture.md)。

## 测试

```bash
cargo test          # 单元 + 集成测试（内存 SQLite + mock DeepSeek）
cargo clippy -- -D warnings
cargo fmt
```

## 目录速览

- `src/`：axum 服务端（routers → services → drivers 分层 + tasks 定时任务）
- `admin-ui/`：Vue3 + antd 管理页（构建产物 `dist/` 随二进制发布）
- `deploy/`：systemd unit + 配置样例
- `tool/`：迁移脚本（`migrations/001-init.sql`）+ 版本指针（`db_version`）
- `docs/`：架构与部署运维主题文档
