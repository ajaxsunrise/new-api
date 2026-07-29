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
- [Docker 部署（参考）](#docker-部署参考)

---

## 环境要求

| 依赖 | 版本要求 | 说明 |
|------|---------|------|
| Go | >= 1.22 | 后端编译 |
| Bun | >= 1.0 | 前端包管理与构建（推荐） |
| Node.js | >= 18 | 可替代 Bun（不推荐） |
| Git | 任意 | 拉取代码 |

## 构建前端

前端位于 `web/` 目录，基于 React 18 + Vite 构建，产出静态文件到 `web/dist/`。

### 1. 安装依赖

```bash
cd web
bun install
```

### 2. 构建

```bash
# 方式一：直接构建
bun run build

# 方式二：带版本号构建（推荐，版本号会注入到前端）
DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$(cat ../VERSION) bun run build
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

# 推荐：带版本号 + 裁剪符号表（体积更小）
go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" -o new-api
```

参数说明：

| 参数 | 说明 |
|------|------|
| `-s -w` | 裁剪调试信息和符号表，减小二进制体积 |
| `-X '...Version=...'` | 将版本号注入到 `common.Version` 变量 |
| `-o new-api` | 指定输出文件名 |

编译完成后，当前目录下生成 `new-api` 可执行文件。

### 完整的一键构建脚本

```bash
#!/bin/bash
set -e

# 1. 构建前端
cd web
bun install
DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$(cat ../VERSION) bun run build
cd ..

# 2. 构建后端
go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" -o new-api

echo "构建完成: ./new-api"
```

## 交叉编译

如需在其他平台上运行，使用 Go 的交叉编译能力：

```bash
# Linux AMD64
GOOS=linux GOARCH=amd64 go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" -o new-api-linux-amd64

# Linux ARM64
GOOS=linux GOARCH=arm64 go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" -o new-api-linux-arm64

# macOS AMD64
GOOS=darwin GOARCH=amd64 go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" -o new-api-darwin-amd64

# macOS ARM64 (Apple Silicon)
GOOS=darwin GOARCH=arm64 go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" -o new-api-darwin-arm64

# Windows AMD64
GOOS=windows GOARCH=amd64 go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" -o new-api-windows-amd64.exe
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
1. git clone <repo> && cd new-api
2. cd web && bun install && bun run build && cd ..
3. go build -ldflags "-s -w -X 'github.com/QuantumNous/new-api/common.Version=$(cat VERSION)'" -o new-api
4. cp .env.example .env  # 编辑 .env，至少配置 SESSION_SECRET 和 SQL_DSN
5. ./new-api             # 或 ./start.sh / systemctl start new-api
6. 访问 http://localhost:3000
```
