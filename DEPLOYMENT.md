# QuanAgent 生产环境部署指南

> 基于 Ubuntu 24.04 + 宝塔面板 + Docker 的完整部署方案

## 📋 部署信息

- **项目**: QuanAgent (Fork from Dify)
- **服务器**: Ubuntu 24.04.3 LTS
- **管理面板**: 宝塔面板
- **容器化**: Docker + Docker Compose
- **反向代理**: Nginx
- **SSL**: Let's Encrypt (自动续期)
- **域名**: agent.quanapps.com
- **部署时间**: 约 20-30 分钟

## 🏗️ 架构概览

```
Internet
    │
    ├─ HTTPS (443) ─────────────────────┐
    └─ HTTP (80) ──── 自动跳转 HTTPS ───┘
                            │
                    ┌───────▼────────┐
                    │  Nginx (宝塔)   │  SSL 终止 + 反向代理
                    └───────┬────────┘
                            │
            ┌───────────────┴───────────────┐
            │                               │
    ┌───────▼────────┐              ┌──────▼───────┐
    │  Web (3000)    │              │  API (5001)  │
    │  Next.js 15    │              │  Flask       │
    └────────────────┘              └──────┬───────┘
                                           │
                    ┌──────────────────────┼──────────────────────┐
                    │                      │                      │
            ┌───────▼────────┐    ┌───────▼────────┐    ┌───────▼────────┐
            │  PostgreSQL    │    │     Redis      │    │    Weaviate    │
            │    (5432)      │    │     (6379)     │    │     (8080)     │
            └────────────────┘    └────────────────┘    └────────────────┘
```

## 🛠️ 前置要求

### 硬件要求
- **CPU**: >= 4 核（推荐 8 核）
- **内存**: >= 8 GB（推荐 16 GB）
- **磁盘**: >= 50 GB SSD
- **网络**: 公网 IP 和域名（用于 SSL）

### 软件要求
- Ubuntu 24.04.3 LTS
- Docker >= 20.10
- Docker Compose >= 2.0
- Nginx（宝塔面板已包含）
- Git

## 📦 部署步骤

### 步骤 1: 连接服务器

```bash
ssh root@YOUR_SERVER_IP
```

### 步骤 2: 安装基础软件

```bash
# 更新系统
apt update && apt upgrade -y

# 安装 Docker（使用官方脚本）
curl -fsSL https://get.docker.com | sh

# 启动 Docker 并设置开机自启
systemctl start docker
systemctl enable docker

# 验证 Docker 安装
docker --version
docker compose version

# 安装 Git
apt install -y git
```

### 步骤 3: 克隆项目

```bash
# 创建项目目录
mkdir -p /www/wwwroot
cd /www/wwwroot

# 克隆项目
git clone https://github.com/paulchen180616/QuanAgent.git
cd QuanAgent
```

### 步骤 4: 配置环境变量

```bash
cd docker

# 复制环境变量模板
cp .env.example .env

# 编辑环境变量
vim .env
```

**重要配置项**（根据实际情况修改）：

```bash
# 域名配置（替换为你的域名）
CONSOLE_API_URL=https://agent.quanapps.com
CONSOLE_WEB_URL=https://agent.quanapps.com
SERVICE_API_URL=https://agent.quanapps.com
APP_API_URL=https://agent.quanapps.com
APP_WEB_URL=https://agent.quanapps.com

# 数据库配置（建议修改密码）
POSTGRES_PASSWORD=your_secure_password

# Secret Key（必须修改！）
SECRET_KEY=$(openssl rand -base64 42)

# 其他配置保持默认即可
```

### 步骤 5: 处理端口冲突（重要！）

宝塔的 Nginx 已占用 80/443 端口，需要：

#### 5.1 禁用 Docker Compose 中的内置 Nginx

```bash
cd /www/wwwroot/QuanAgent/docker

# 注释掉 nginx 服务（自动化脚本）
cat > /tmp/disable_nginx.py << 'EOF'
import re

with open('docker-compose.yaml', 'r') as f:
    content = f.read()

lines = content.split('\n')
in_nginx = False
nginx_indent = 0
result = []

for line in lines:
    stripped = line.lstrip()
    current_indent = len(line) - len(stripped)
    
    if stripped.startswith('nginx:') and not line.strip().startswith('#'):
        in_nginx = True
        nginx_indent = current_indent
        result.append('  # ' + line.lstrip())
        continue
    
    if in_nginx:
        if stripped and current_indent <= nginx_indent:
            in_nginx = False
            result.append(line)
        else:
            if stripped:
                result.append('  # ' + line.lstrip())
            else:
                result.append(line)
    else:
        result.append(line)

with open('docker-compose.yaml', 'w') as f:
    f.write('\n'.join(result))

print("✅ nginx 服务已禁用")
EOF

python3 /tmp/disable_nginx.py
```

#### 5.2 添加端口映射

```bash
# 为 web 和 api 服务添加端口映射
cat > /tmp/add_ports.py << 'EOF'
import re

with open('docker-compose.yaml', 'r') as f:
    content = f.read()

# 为 web 服务添加端口
content = re.sub(
    r'(  web:\n    image: quanagent-web:1\.10\.1)',
    r'\1\n    ports:\n      - "3000:3000"',
    content
)

# 为 api 服务添加端口
content = re.sub(
    r'(  api:\n    image: langgenius/dify-api:1\.10\.1)',
    r'\1\n    ports:\n      - "5001:5001"',
    content
)

with open('docker-compose.yaml', 'w') as f:
    f.write(content)

print("✅ 端口映射已添加")
EOF

python3 /tmp/add_ports.py
```

### 步骤 6: 构建前端镜像

```bash
cd /www/wwwroot/QuanAgent/docker

# 构建自定义前端镜像
docker build -f docker-compose-web.yaml -t quanagent-web:1.10.1 ../web

# 验证镜像
docker images | grep quanagent-web
```

### 步骤 7: 创建并配置 Docker volumes

```bash
cd /www/wwwroot/QuanAgent/docker

# 创建 volume 目录
mkdir -p volumes/app/storage volumes/plugin_daemon volumes/db volumes/redis volumes/sandbox

# 设置正确的权限（重要！）
chown -R 1001:1001 volumes/app
chown -R 1001:1001 volumes/plugin_daemon
chown -R 70:70 volumes/db
chown -R 999:999 volumes/redis
chown -R 1001:1001 volumes/sandbox

# 设置目录权限
chmod -R 755 volumes/
```

### 步骤 8: 启动服务

```bash
cd /www/wwwroot/QuanAgent/docker

# 启动所有服务
docker compose up -d

# 等待服务启动（约 30 秒）
sleep 30

# 检查服务状态
docker compose ps
```

**预期输出**：所有服务状态应为 `Up` 或 `healthy`

### 步骤 9: 修复数据库问题（如果出现）

如果 `plugin_daemon` 报错 `database "dify_plugin" does not exist`：

```bash
# 创建缺失的数据库
docker exec -it docker-db_postgres-1 psql -U postgres -c "CREATE DATABASE dify_plugin;"

# 重启 plugin_daemon 服务
docker compose restart plugin_daemon
```

### 步骤 10: 配置 Nginx 反向代理

#### 10.1 DNS 配置

在你的域名管理后台添加 A 记录：

```
类型: A
主机记录: agent  (或其他子域名)
记录值: YOUR_SERVER_IP
TTL: 600
```

等待 DNS 生效（1-10 分钟）：

```bash
# 验证 DNS
ping agent.quanapps.com
nslookup agent.quanapps.com
```

#### 10.2 创建 Nginx 配置

```bash
# 创建 HTTP 配置（先不配置 SSL）
cat > /www/server/panel/vhost/nginx/agent.quanapps.com.conf << 'EOF'
server {
    listen 80;
    server_name agent.quanapps.com;
    
    access_log /www/wwwlogs/agent.quanapps.com_access.log;
    error_log /www/wwwlogs/agent.quanapps.com_error.log;

    # 前端路由
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 3600s;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }

    # API 路由
    location ~ ^/(api|console/api|v1|files) {
        proxy_pass http://127.0.0.1:5001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 3600s;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
        proxy_request_buffering off;
        client_max_body_size 1024m;
    }
}
EOF

# 测试配置
nginx -t

# 重新加载 Nginx
nginx -s reload

# 测试 HTTP 访问
curl -I http://agent.quanapps.com/
```

### 步骤 11: 配置 SSL 证书

#### 方法 A：宝塔面板 UI（推荐）

1. 登录宝塔面板
2. **网站** → 找到站点或点击"添加站点"
3. **设置** → **SSL**
4. 选择 **Let's Encrypt**
5. 勾选域名，点击"申请"
6. 开启 **强制 HTTPS**

#### 方法 B：命令行

```bash
# 安装 certbot
apt install -y certbot python3-certbot-nginx

# 申请证书（交互式）
certbot --nginx -d agent.quanapps.com

# 或非交互式
certbot --nginx -d agent.quanapps.com \
  --email your@email.com \
  --agree-tos \
  --no-eff-email \
  --redirect
```

#### 方法 C：手动配置 SSL

如果宝塔已申请证书，更新 Nginx 配置：

```bash
cat > /www/server/panel/vhost/nginx/agent.quanapps.com.conf << 'EOF'
server {
    listen 80;
    server_name agent.quanapps.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl;
    server_name agent.quanapps.com;
    
    # SSL 证书（宝塔路径）
    ssl_certificate /www/server/panel/vhost/cert/agent.quanapps.com/fullchain.pem;
    ssl_certificate_key /www/server/panel/vhost/cert/agent.quanapps.com/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    http2 on;
    
    access_log /www/wwwlogs/agent.quanapps.com_access.log;
    error_log /www/wwwlogs/agent.quanapps.com_error.log;

    # 前端路由
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 3600s;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }

    # API 路由
    location ~ ^/(api|console/api|v1|files) {
        proxy_pass http://127.0.0.1:5001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 3600s;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
        proxy_request_buffering off;
        client_max_body_size 1024m;
    }
}
EOF

nginx -t && nginx -s reload
```

### 步骤 12: 更新环境变量为 HTTPS

```bash
cd /www/wwwroot/QuanAgent/docker

# 备份
cp .env .env.backup

# 更新为 HTTPS
sed -i 's|http://agent.quanapps.com|https://agent.quanapps.com|g' .env

# 重启服务
docker compose restart api web

# 等待服务启动
sleep 5

# 验证
docker compose ps
```

### 步骤 13: 验证部署

```bash
# 测试 HTTPS 访问
curl -I https://agent.quanapps.com/

# 测试服务状态
docker compose ps

# 查看日志（可选）
docker compose logs -f --tail=50
```

## ✅ 首次使用

### 1. 访问系统

在浏览器打开：`https://agent.quanapps.com/`

### 2. 创建管理员账号

首次访问会提示创建管理员账号：

```
邮箱: admin@your-domain.com
用户名: admin
密码: [设置强密码]
```

### 3. 配置 LLM 模型

登录后：
1. 进入 **设置** → **模型供应商**
2. 添加 API Key：
   - OpenAI
   - Anthropic Claude
   - Azure OpenAI
   - 或国内模型（智谱、通义千问等）

### 4. 创建应用

点击 **创建应用**，选择模板或从头开始构建你的 AI Agent！

## 🔧 运维管理

### 常用命令

```bash
# 进入项目目录
cd /www/wwwroot/QuanAgent/docker

# 查看服务状态
docker compose ps

# 查看日志
docker compose logs -f api          # API 日志
docker compose logs -f web          # 前端日志
docker compose logs -f worker       # Worker 日志
docker compose logs --tail=100      # 所有服务最后 100 行日志

# 重启服务
docker compose restart api web      # 重启指定服务
docker compose restart              # 重启所有服务

# 停止服务
docker compose stop

# 启动服务
docker compose up -d

# 完全重启（包括数据库）
docker compose down
docker compose up -d

# 更新代码
cd /www/wwwroot/QuanAgent
git pull
cd docker
docker compose down
docker compose up -d --build
```

### 备份数据

```bash
# 备份数据库
docker exec docker-db_postgres-1 pg_dump -U postgres dify > /backup/dify_$(date +%Y%m%d).sql

# 备份 volume 数据
tar -czf /backup/quanagent_volumes_$(date +%Y%m%d).tar.gz /www/wwwroot/QuanAgent/docker/volumes/

# 备份环境变量
cp /www/wwwroot/QuanAgent/docker/.env /backup/.env.$(date +%Y%m%d)
```

### 恢复数据

```bash
# 恢复数据库
docker exec -i docker-db_postgres-1 psql -U postgres dify < /backup/dify_20251209.sql

# 恢复 volumes
tar -xzf /backup/quanagent_volumes_20251209.tar.gz -C /
```

### 监控和日志

```bash
# 实时监控资源使用
docker stats

# 查看 Nginx 日志
tail -f /www/wwwlogs/agent.quanapps.com_access.log
tail -f /www/wwwlogs/agent.quanapps.com_error.log

# 查看 Docker 磁盘使用
docker system df

# 清理未使用的镜像和容器
docker system prune -a
```

### SSL 证书自动续期

宝塔面板会自动续期 Let's Encrypt 证书，无需手动操作。

如果使用 certbot，添加自动续期：

```bash
# 测试续期
certbot renew --dry-run

# Certbot 会自动添加 cron job，无需手动配置
```

## ⚠️ 常见问题

### 问题 1: 端口被占用

**错误**: `failed to bind host port 0.0.0.0:80/tcp: address already in use`

**解决**:
1. 禁用 Docker Compose 中的 nginx 服务
2. 为 web 和 api 添加端口映射
3. 使用宝塔 Nginx 作为反向代理

### 问题 2: 数据库连接失败

**错误**: `database "dify_plugin" does not exist`

**解决**:
```bash
docker exec -it docker-db_postgres-1 psql -U postgres -c "CREATE DATABASE dify_plugin;"
docker compose restart plugin_daemon
```

### 问题 3: 权限错误

**错误**: `PermissionDenied at write => permission denied`

**解决**:
```bash
cd /www/wwwroot/QuanAgent/docker
docker compose down
chown -R 1001:1001 volumes/app
chown -R 1001:1001 volumes/plugin_daemon
chmod -R 755 volumes/
docker compose up -d
```

### 问题 4: SSL 证书路径错误

**错误**: `cannot load certificate ... no such file`

**解决**:
```bash
# 查找证书位置
ls -lh /www/server/panel/vhost/cert/agent.quanapps.com/

# 或
certbot certificates

# 更新 Nginx 配置中的证书路径
```

### 问题 5: 看到宝塔默认页面

**原因**: Nginx 配置未正确设置反向代理

**解决**: 按照步骤 10 和 11 重新配置 Nginx

## 📚 参考资源

- **项目地址**: https://github.com/paulchen180616/QuanAgent
- **上游项目**: https://github.com/langgenius/dify
- **Docker 文档**: https://docs.docker.com/
- **Nginx 文档**: https://nginx.org/en/docs/
- **Let's Encrypt**: https://letsencrypt.org/

## 🎯 性能优化建议

### 1. 数据库优化

编辑 `docker-compose.yaml` 中的 PostgreSQL 配置：

```yaml
db_postgres:
  environment:
    POSTGRES_DB: dify
    POSTGRES_USER: postgres
    POSTGRES_PASSWORD: difyai123456
    # 添加性能配置
    POSTGRES_INITDB_ARGS: "-E UTF8 --locale=C"
  command: >
    postgres
    -c max_connections=200
    -c shared_buffers=256MB
    -c effective_cache_size=1GB
```

### 2. Redis 持久化

```yaml
redis:
  command: redis-server --save 60 1 --loglevel warning
  volumes:
    - ./volumes/redis/data:/data
```

### 3. Nginx 缓存

在 Nginx 配置中添加静态资源缓存：

```nginx
location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2)$ {
    proxy_pass http://127.0.0.1:3000;
    expires 7d;
    add_header Cache-Control "public, immutable";
}
```

## 🔒 安全建议

1. **修改默认密码**: 更改 `.env` 中的所有默认密码
2. **防火墙配置**: 只开放 80、443、SSH 端口
3. **定期更新**: 定期更新 Docker 镜像和系统软件包
4. **备份策略**: 每日自动备份数据库和关键数据
5. **日志审计**: 定期检查 Nginx 和应用日志

## 📞 技术支持

如遇问题，请：
1. 检查本文档的"常见问题"部分
2. 查看日志：`docker compose logs -f`
3. 在 GitHub 提交 Issue

---

**部署完成！** 🎉

祝你使用 QuanAgent 构建出色的 AI 应用！
