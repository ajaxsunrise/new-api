# 二进制部署文档

本文档介绍如何从源码构建前后端二进制包，并通过配置启动服务。

---

## 目录

- [环境要求](#环境要求)
- [构建前端](#构建前端)
- [构建后端](#构建后端)
- [交叉编译](#交叉编译)
- [配置说明](#配置说明)
- [启动服务](#启动服务)
- [停止与重启](#停止与重启)
- [从 rc.22 升级到 rc.50](#从-rc22-升级到-rc50)
- [Docker 部署（参考）](#docker-部署参考)

---

## 环境要求

| 依赖 | 版本要求 | 说明 |
|------|---------|------|
| Go | >= 1.26（以 `go.mod` 为准） | 后端编译 |
| Bun | >= 1.0 | 前端包管理与构建 |
| Git | 任意 | 拉取代码、生成版本号 |

## 构建前端

前端位于 `web/` 目录，基于 React 19 + Rsbuild 构建，产出静态文件到 `web/dist/`。

### 1. 安装依赖

```bash
cd web
bun install
```

### 2. 构建

```bash
# 方式一：直接构建
bun run build

# 方式二：带版本号构建（推荐，版本号会注入到前端；与官方 CI 一致）
DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$(cd .. && git describe --tags --match 'v[0-9]*') bun run build
```

构建完成后，静态文件输出到 `web/dist/`。

> **注意**：前端构建产物会被后端通过 Go 的 `embed` 机制嵌入到二进制文件中（见 `main.go` 中的 `//go:embed web/dist`），因此前端必须在后端编译之前完成构建。

## 构建后端

### 1. 下载 Go 依赖

```bash
go mod download
```

### 2. 编译

```bash
# 基础编译
go build -o new-api

# 推荐：与官方 CI 一致（PGO 优化 + 版本号注入 + 静态链接 + 裁剪符号表）
VERSION=$(git describe --tags --match 'v[0-9]*')
go build -pgo="$(go list -m -f '{{.Dir}}' github.com/MoeForge/moejs)/default.pgo" \
  -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$VERSION' -extldflags '-static'" \
  -o new-api
```

参数说明：

| 参数 | 说明 |
|------|------|
| `-s -w` | 裁剪调试信息和符号表，减小二进制体积 |
| `-X '...Version=...'` | 将版本号注入到 `common.Version` 变量（仓库内 `VERSION` 文件为空，版本号来自 `git describe`，也可用环境变量 `VERSION` 在运行时覆盖） |
| `-pgo .../moejs/default.pgo` | 按 moejs（JS 插件运行时）的性能 profile 做 PGO 编译优化，官方 CI 使用 |
| `-extldflags '-static'` | 静态链接，产物不依赖系统库 |
| `-o new-api` | 指定输出文件名 |

编译完成后，当前目录下生成 `new-api` 可执行文件。

### 完整的一键构建脚本

```bash
#!/bin/bash
set -e
VERSION=$(git describe --tags --match 'v[0-9]*')

# 1. 构建前端
cd web
bun install --frozen-lockfile
DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$VERSION bun run build
cd ..

# 2. 构建后端
go build -pgo="$(go list -m -f '{{.Dir}}' github.com/MoeForge/moejs)/default.pgo" \
  -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$VERSION' -extldflags '-static'" \
  -o new-api

echo "构建完成: ./new-api ($VERSION)"
```

## 交叉编译

如需在其他平台上运行，使用 Go 的交叉编译能力（版本号统一用 `VERSION=$(git describe --tags --match 'v[0-9]*')` 生成）：

```bash
VERSION=$(git describe --tags --match 'v[0-9]*')

# Linux AMD64
GOOS=linux GOARCH=amd64 go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$VERSION'" -o new-api-linux-amd64

# Linux ARM64
GOOS=linux GOARCH=arm64 go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$VERSION'" -o new-api-linux-arm64

# macOS AMD64
GOOS=darwin GOARCH=amd64 go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$VERSION'" -o new-api-darwin-amd64

# macOS ARM64 (Apple Silicon)
GOOS=darwin GOARCH=arm64 go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$VERSION'" -o new-api-darwin-arm64

# Windows AMD64
GOOS=windows GOARCH=amd64 go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$VERSION'" -o new-api-windows-amd64.exe
```

> **注意**：如果启用了 CGO（如依赖 SQLite 的 CGO 驱动），交叉编译需要对应平台的 C 工具链。默认 `CGO_ENABLED=0` 编译为纯静态二进制，使用 Go 内置的 SQLite 驱动。

## 配置说明

服务通过**环境变量**或 `.env` 文件进行配置。在二进制所在目录创建 `.env` 文件，或通过系统环境变量传入。

### 最小配置

创建 `.env` 文件：

```env
# 必填：会话密钥，多机部署时必须一致
SESSION_SECRET=your-random-secret-string

# 数据库连接（三选一）
# SQLite（默认，无需配置，自动创建 one-api.db）
# MySQL
SQL_DSN=root:password@tcp(127.0.0.1:3306)/newapi?parseTime=true
# PostgreSQL
SQL_DSN=postgres://user:password@127.0.0.1:5432/newapi?sslmode=disable

# 服务端口（默认 3000）
PORT=3000
```

### 完整配置项

复制 `.env.example` 作为模板：

```bash
cp .env.example .env
```

#### 核心配置

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PORT` | `3000` | 服务监听端口 |
| `SESSION_SECRET` | - | 会话加密密钥（**必填**） |
| `CRYPTO_SECRET` | 同 SESSION_SECRET | 数据加密密钥 |
| `FRONTEND_BASE_URL` | - | 前端基础 URL |

#### 数据库配置

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `SQL_DSN` | - | 数据库连接字符串，支持 MySQL / PostgreSQL / SQLite |
| `LOG_SQL_DSN` | - | 日志库连接字符串（可选，分离日志存储） |
| `SQLITE_PATH` | `one-api.db?_busy_timeout=30000` | SQLite 数据库路径 |
| `SQL_MAX_IDLE_CONNS` | `100` | 最大空闲连接数 |
| `SQL_MAX_OPEN_CONNS` | `1000` | 最大打开连接数 |
| `SQL_MAX_LIFETIME` | `60` | 连接最大生命周期（秒） |

**SQL_DSN 格式示例：**

```env
# MySQL
SQL_DSN=user:password@tcp(127.0.0.1:3306)/dbname?parseTime=true

# PostgreSQL
SQL_DSN=postgres://user:password@127.0.0.1:5432/dbname?sslmode=disable

# SQLite（留空 SQL_DSN，使用 SQLITE_PATH）
SQLITE_PATH=/data/new-api.db
```

#### 缓存配置

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `REDIS_CONN_STRING` | - | Redis 连接字符串，如 `redis://localhost:6379/0` |
| `MEMORY_CACHE_ENABLED` | `false` | 启用内存缓存 |
| `SYNC_FREQUENCY` | `60` | 缓存同步频率（秒） |
| `BATCH_UPDATE_ENABLED` | `false` | 启用批量更新 |
| `BATCH_UPDATE_INTERVAL` | `5` | 批量更新间隔（秒） |

> 启用 Redis 后会自动启用内存缓存。

#### 节点与集群

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `NODE_TYPE` | `master` | 节点类型：`master`（主节点）或 `slave`（从节点） |

多节点部署时，所有节点连接同一个数据库和 Redis，主节点负责定时任务。

#### 超时与限流

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `RELAY_TIMEOUT` | `0` | 请求超时（秒），0 表示不限 |
| `STREAMING_TIMEOUT` | `300` | 流式响应超时（秒） |
| `GLOBAL_API_RATE_LIMIT` | `180` | API 全局限流次数 |
| `GLOBAL_API_RATE_LIMIT_DURATION` | `180` | API 限流窗口（秒） |

#### 功能开关

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DEBUG` | `false` | 调试模式 |
| `ENABLE_PPROF` | `false` | 启用 pprof 性能分析 |
| `GENERATE_DEFAULT_TOKEN` | `false` | 启动时生成默认 API Token |
| `CHANNEL_UPDATE_FREQUENCY` | - | 渠道自动更新频率（秒） |

#### OAuth 与登录

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `GITHUB_CLIENT_ID` | - | GitHub OAuth Client ID |
| `GITHUB_CLIENT_SECRET` | - | GitHub OAuth Client Secret |
| `PASSWORD_LOGIN_ENABLED` | `true` | 允许密码登录 |
| `PASSWORD_REGISTER_ENABLED` | `true` | 允许密码注册 |
| `REGISTER_ENABLED` | `true` | 允许注册 |

#### 邮件

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `SMTP_SERVER` | - | SMTP 服务器地址 |
| `SMTP_PORT` | `587` | SMTP 端口 |
| `SMTP_ACCOUNT` | - | SMTP 账号 |
| `SMTP_FROM` | - | 发件人地址 |
| `SMTPTOKEN` | - | SMTP 认证令牌 |
| `EMAIL_VERIFICATION_ENABLED` | `false` | 启用邮箱验证 |

## 启动服务

### 前台启动（调试用）

```bash
./new-api
```

### 后台启动

```bash
nohup ./new-api > logs/server.log 2>&1 &
echo $! > .server.pid
```

### 使用项目脚本

项目提供了便捷的管理脚本：

```bash
# 启动
./start.sh

# 停止
./stop.sh

# 重启
./restart.sh
```

`start.sh` 的行为：
- 若当前目录存在编译好的 `new-api` 二进制，则直接运行
- 若不存在，则使用 `go run main.go` 运行（适合开发环境）
- PID 记录在 `.server.pid`，日志输出到 `logs/server.log`

### 通过 systemd 管理（生产推荐）

创建 `/etc/systemd/system/new-api.service`：

```ini
[Unit]
Description=New API Service
After=network.target

[Service]
Type=simple
User=newapi
WorkingDirectory=/opt/new-api
ExecStart=/opt/new-api/new-api
Restart=always
RestartSec=5
EnvironmentFile=/opt/new-api/.env

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable new-api
sudo systemctl start new-api

# 查看状态
sudo systemctl status new-api

# 查看日志
sudo journalctl -u new-api -f
```

## 停止与重启

```bash
# 使用脚本
./stop.sh       # 停止（先通过 PID 文件，再通过端口 3000 查找进程）
./restart.sh    # 先停止，等待端口释放后启动

# 手动停止
kill $(cat .server.pid)
```

## 从 rc.22 升级到 rc.50

rc.23 起上游将 task 适配器（doubao/sora/kling 等）从 Go 代码迁移为 JS 插件（`plugins/tasks/`，由 moejs 执行），并重写了 git 历史，因此升级方式为**整包替换二进制**，不能用 `git pull` 增量更新。

### 兼容性（已在生产库副本上验证）

- 数据库迁移为**纯增量**：新增 `task_plugins`、`user_access_tokens`、`audit_logs`、`login_encryption_keys` 四张表，及 `tokens.auto_groups`、`users.access_token_created_at` 等若干列，无删除或重命名，PostgreSQL 上自动完成
- 用户/渠道/Token/日志数据完全保留
- `.env` 配置项（`SQL_DSN`、`SESSION_SECRET`、`REDIS_CONN_STRING` 等）无需改动
- 注意：dashboard 会话机制有变更，升级后管理员和用户可能需要重新登录

### 升级步骤

```bash
# 1. 备份数据库（回滚依据）
set -a; source .env; set +a
mkdir -p ~/backups
pg_dump "$SQL_DSN" > ~/backups/db_new_api_$(date +%Y%m%d_%H%M).sql

# 2. 备份旧二进制
cp new-api new-api-rc22.bak

# 3. 构建新包（见上文"完整的一键构建脚本"，需在 rc50-local 分支）

# 4. 重启（自动完成数据库迁移）
./restart.sh

# 5. 验证
curl -s http://localhost:3000/api/status | grep -o '"version":"[^"]*"'
```

### 回滚

```bash
./stop.sh
cp new-api-rc22.bak new-api
# 恢复数据库（迁移是增量的，不恢复数据库通常也能跑，但完整回滚以备份为准）
set -a; source .env; set +a
psql "$SQL_DSN" -c "DROP DATABASE db_new_api;"
psql "$SQL_DSN" -c "CREATE DATABASE db_new_api;"
psql "$SQL_DSN" -f ~/backups/db_new_api_<备份时间>.sql
./start.sh
```

## Docker 部署（参考）

项目自带 `Dockerfile`，支持多阶段构建：

```bash
# 构建镜像
docker build -t new-api .

# 运行
docker run -d \
  --name new-api \
  -p 3000:3000 \
  -v /data/new-api:/data \
  -e SESSION_SECRET=your-secret \
  -e SQL_DSN="root:password@tcp(mysql:3306)/newapi?parseTime=true" \
  new-api
```

Dockerfile 的构建流程：
1. 阶段一（Bun）：安装前端依赖 + 构建前端 → `web/dist/`
2. 阶段二（Go）：编译后端，嵌入前端产物 → `new-api` 二进制
3. 阶段三（Debian Slim）：最终运行镜像，仅包含二进制和必要依赖

---

## 典型部署流程总结

```
1. git clone <repo> && cd new-api && git checkout rc50-local
2. VERSION=$(git describe --tags --match 'v[0-9]*')
3. cd web && bun install && DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$VERSION bun run build && cd ..
4. go build -pgo="$(go list -m -f '{{.Dir}}' github.com/MoeForge/moejs)/default.pgo" \
     -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$VERSION' -extldflags '-static'" -o new-api
5. cp .env.example .env  # 编辑 .env，至少配置 SESSION_SECRET 和 SQL_DSN
6. ./new-api             # 或 ./start.sh / systemctl start new-api
7. 访问 http://localhost:3000
```
