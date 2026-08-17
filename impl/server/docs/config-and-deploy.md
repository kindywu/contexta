# Contexta Server 配置与部署

> 主题文档：云主机选型、构建、安装（systemd）、备份、首次启动顺序，以及**部署约束记录**（已裁决语义，改部署/客户端前必读）。配套文件：`deploy/contexta-server.service`、`deploy/config.yaml.example`。

## 1. 云主机选型

- **推荐**：香港/海外轻量云（免 ICP 备案）+ 域名 + Caddy 自动 HTTPS。国内云需 ICP 备案（周期 1-3 周），beta 期不建议
- 备选：Cloudflare Tunnel（不买域名时）
- **时区必须设为上海**（硬依赖，见 §8 约束 TZ）：

```bash
timedatectl set-timezone Asia/Shanghai
timedatectl   # 确认 Local time 为 Asia/Shanghai
```

## 2. 反向代理（Caddy 自动 HTTPS）

服务端直接监听 `127.0.0.1:8080` 即可（或 `0.0.0.0:8080` 由 Caddy 反代到内网）。Caddy 一行起服务（或写 Caddyfile）：

```bash
# 方式一：命令行
caddy reverse-proxy --from api.example.com --to localhost:8080

# 方式二：Caddyfile（/etc/caddy/Caddyfile）
api.example.com {
    reverse_proxy localhost:8080
}
```

- App 端构建时指定 `--dart-define=SERVER_BASE_URL=https://api.example.com`
- HTTPS 必须（App 端明文 HTTP 会被平台限制）；TLS 证书由 Caddy 自动申请续期

## 3. 配置（环境变量）

**敏感值（DEEPSEEK_API_KEY / JWT_SECRET / ADMIN_INIT_PASSWORD）只走 `/etc/contexta/env`**（systemd `EnvironmentFile` 加载），不写入任何仓库文件。`deploy/config.yaml.example` 为 env 对照清单（全部可选项除标注必须的）：

| 变量 | 默认 | 说明 |
|---|---|---|
| `PORT` | `8080` | 监听端口 |
| `DB_PATH` | `contexta.db` | SQLite 文件路径（生产：`/opt/contexta/contexta.db`） |
| `WORD_QUOTA_DAILY` | `200` | 用户每日查词配额（真实 LLM 调用次数） |
| `ARTICLE_BUDGET_DAILY` | `100` | 单日文章生成预算（防补生成循环烧钱） |
| `DAILY_GENERATE_HOUR` | `3` | 每日文章生成时刻（点；实际触发为整点后 1 分钟） |
| `LLM_TIMEOUT_SECS` | `90` | 单次 LLM 调用总预算（含重试退避） |
| `DEEPSEEK_MODEL` | `deepseek-v4-flash` | 模型名 |
| `DEEPSEEK_BASE_URL` | `https://api.deepseek.com` | 可换网关 |
| `CHINADAILY_BASE_URL` | `https://www.chinadaily.com.cn` | 事实源抓取基址（NEWS 事实锚定，需服务器出网可达） |
| `SOURCE_MAX_AGE_DAYS` | `3` | 只选近 N 天来源（新鲜度窗口） |
| `SOURCE_FETCH_TIMEOUT_SECS` | `15` | chinadaily 单请求兜底超时 |
| `RECENT_TITLE_DAYS` | `14` | 标题防重注入窗口（近 N 天已生成标题清单） |
| `CACHE_TTL_DAYS` | `30` | 查词缓存 TTL |
| `CACHE_MAX_ROWS` | `5000` | 查词缓存条数上限（超限删最旧） |
| `JWT_SECRET` | **必须** | 生成：`openssl rand -hex 32`（**<32 字符直接启动失败**，见 §8） |
| `DEEPSEEK_API_KEY` | **必须** | DeepSeek API key（缺失启动失败） |
| `ADMIN_INIT_PASSWORD` | 无 | **首次启动必须**；seed 后可从 env 移除（见 §6） |

## 4. 构建

```bash
# 1) 管理页静态资源（提前执行，dist 需存在——二进制用 rust-embed 嵌入）
cd impl/server/admin-ui
npm install && npm run build     # 产出 admin-ui/dist/（已提交仓库）

# 2) 服务端 release 构建
cd impl/server
cargo build --release            # 产出 target/release/server（单二进制）
```

## 5. 安装（rsync + systemctl）

```bash
# 目录与 unit 文件
sudo mkdir -p /opt/contexta /etc/contexta
sudo rsync -a target/release/server /opt/contexta/server
sudo cp deploy/contexta-server.service /etc/systemd/system/contexta-server.service

# 敏感配置（权限 600，只 root 可读）
sudo tee /etc/contexta/env <<'EOF'
PORT=8080
DB_PATH=/opt/contexta/contexta.db
JWT_SECRET=<openssl rand -hex 32 生成>
DEEPSEEK_API_KEY=<key>
ADMIN_INIT_PASSWORD=<首次启动用，seed 后移除>
EOF
sudo chmod 600 /etc/contexta/env

# 启动并开机自启
sudo systemctl daemon-reload
sudo systemctl enable --now contexta-server
sudo systemctl status contexta-server
```

**升级流程**：`rsync -a` 新二进制 → `sudo systemctl restart contexta-server`（SQLite 数据文件不动）。

## 6. 首次启动顺序

1. 设置 `ADMIN_INIT_PASSWORD` 到 `/etc/contexta/env`（seed 后即可从 env 移除，下次启动不再覆盖——已有 admin 行则跳过 seed）
2. `systemctl start contexta-server`——启动时自动：连库 + 001 迁移 + seed admin（username `admin`）+ **补生成今天与明天的文章**（任务侧，LLM 调用）
3. 登录管理页 `https://api.example.com/admin`，用 `admin` + 初始密码
4. 若启动时补生成失败或当天已过审文章不足，**手动补生成今天**：
   ```bash
   curl -X POST https://api.example.com/api/admin/articles/generate \
     -H "Authorization: Bearer <admin-token>" -H "Content-Type: application/json" \
     -d '{"date":"2026-08-13"}'
   ```
5. 审核：管理页「文章审核」通过今天文章（仅已过审对用户可见）
6. 此后每日 03:01 自动生成明天文章，管理员白天审核

## 7. 备份（每月冷备份）

**备份 = 拷 SQLite 文件**（单文件，含 WAL 时先 checkpoint 或直接用 sqlite3 .backup）：

```bash
mkdir -p /backup
sqlite3 /opt/contexta/contexta.db ".backup /backup/contexta-$(date +%F).db"
```

- **每月做一次冷备份**，沿用仓库根 `.backup/` 纪律：`git add -f .backup/contexta-db-*` 提交最近一次备份；删除任何备份前先确认对象是本次会话产物，**绝不删除既有备份**
- 恢复：停服务 → `sqlite3 /backup/contexta-YYYY-MM-DD.db ".backup /opt/contexta/contexta.db"` → 启动（注意设备端还有 App 本地缓存，恢复会回滚服务端侧数据）

## 8. 部署约束记录（已裁决语义，改部署/客户端前必读）

以下语义已在实现中裁决并落测，部署或对接时**不得按直觉更改**：

| # | 约束 | 裁决语义 | 出处 |
|---|---|---|---|
| 1 | **difficulty 字典序** | `GET /api/articles` 的排序为 `ORDER BY difficulty, order_index`——difficulty 是 TEXT，按 **ASCII 字典序**（HIGH < LOW < MEDIUM），**不是**自然难度序（LOW/MEDIUM/HIGH）。App 端须自行按自然序整理 | article_service `get_approved_by_date` |
| 2 | **非法日期 = 空结果** | 下发接口（`GET /api/articles?date=`）对非法日期**不校验、不 400**，直接查库返回 200 空数组 `data: []`。仅管理端手动补生成（`POST /api/admin/articles/generate`）做严格零填充 ISO 校验（`2026-8-14`、`2026-13-01`、`2026-02-30` 均 400 BAD_PARAM） | routers/articles.rs、routers/admin.rs |
| 3 | **JWT_SECRET ≥ 32 字符** | 启动硬校验，不足直接报错退出（HS256 安全下限）。生成：`openssl rand -hex 32` | config.rs |
| 4 | **TZ 影响配额日界** | 查词配额日界、文章日预算、用量统计、`/api/articles/today` 的"今天"全部按**服务器本地时区**零点（`chrono::Local`）。部署必须 `timedatectl set-timezone Asia/Shanghai`，否则配额日界偏移 8 小时 | services/mod.rs `today_start_millis` |
| 5 | **`\|\|\|` 段落契约** | 段落入库为单列 `英文\|\|\|中文`，下发时按 `\|\|\|` 拆分；无分隔符时整段作英文、中文为空串。服务端**不存第二列** | article_service `generate_one` / `load_view` |
| 6 | **error_code 表** | 服务端错误语义固定为 `{code, message, error_code}`，HTTP 状态码表达类别、body 内 error_code 表达细分。App 端按此映射回现有异常类型（400 QUOTA_EXCEEDED / 401 TOKEN_EXPIRED·EVICTED / 403 BANNED / 500 LLM_FATAL·PIPELINE_BLOCKING / 502 LLM_RECOVERABLE_EXHAUSTED / 504 LLM_TIMEOUT）。**新增错误必须走该表**，不得裸发新状态码 | response.rs，详见 architecture.md §6 |
| 7 | **T9 任务 03:01 触发** | 每日生成时刻 = `DAILY_GENERATE_HOUR` 点**整点后 1 分钟**（默认 03:01，避开整点边界）。启动时另有补漏（今天+明天），与定时循环幂等 | tasks/article_daily_task.rs |
| 8 | **admin 12h TTL** | 管理员 token 有效期 12 小时（App token 30 天）——admin 会话被窃取时缩小暴露窗口 | jwt.rs |
| 9 | **免密直登** | App 登录不校验验证码（beta 简化），预留 `code` 字段将来升级；风险靠封禁兜底 | auth_service.rs |
| 10 | **文章为全局共享池** | 同难度用户读同批文章（3 难度 × 5 篇/天），审核模型下不按用户独立生成；下发需 JWT，与用户查词配额无关 | 设计决策 |

## 9. 运维速查

```bash
systemctl status contexta-server        # 状态
journalctl -u contexta-server -f        # 日志
curl http://localhost:8080/api/health   # 健康检查
```

- 每日生成失败只记日志不阻塞服务：`journalctl -u contexta-server | grep "daily"`，LLM 恢复后下一次 wake（03:01）自动补齐
- 管理页静态资源随二进制嵌入：升级二进制即升级管理页
