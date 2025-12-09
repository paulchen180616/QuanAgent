# QuanAgent 生产环境部署文档

## 服务器信息
- **服务器IP**: 137.184.191.97
- **操作系统**: Ubuntu 24.04.3 LTS
- **管理面板**: 宝塔面板
- **项目地址**: https://github.com/paulchen180616/QuanAgent

## 部署架构
```
                        ┌─────────────────┐
                        │   Nginx (80)    │
                        │  (宝塔/反向代理) │
                        └────────┬────────┘
                                 │
                    ┌────────────┴────────────┐
                    │                         │
          ┌─────────▼─────────┐    ┌─────────▼─────────┐
          │  QuanAgent Web    │    │  QuanAgent API    │
          │    (3000)         │    │    (5001)         │
          └───────────────────┘    └───────────────────┘
                    │                         │
          ┌─────────┴──────────┬──────────────┴─────────┐
          │                    │                         │
    ┌─────▼──────┐      ┌─────▼──────┐         ┌───────▼────────┐
    │ PostgreSQL │      │   Redis    │         │    Weaviate    │
    │   (5432)   │      │   (6379)   │         │     (8080)     │
    └────────────┘      └────────────┘         └────────────────┘
```

## 前置要求

### 系统要求
- CPU >= 4 Core（推荐）
- RAM >= 8 GiB（推荐）
- 磁盘空间 >= 50 GB
- Ubuntu 24.04.3 LTS

### 需要安装的软件
- Docker (>= 20.10)
- Docker Compose (>= 2.0)
- Git
- Nginx（宝塔面板已包含）

## 部署步骤

### 步骤 1: 连接服务器

使用 SSH 连接到服务器：
```bash
ssh root@137.184.191.97
```

### 步骤 2: 安装 Docker 和 Docker Compose

```bash
# 更新包索引
apt update

# 安装必要的依赖
apt install -y ca-certificates curl gnupg lsb-release

# 添加 Docker 官方 GPG 密钥
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# 设置 Docker 仓库
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# 安装 Docker Engine
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 启动 Docker 服务
systemctl start docker
systemctl enable docker

# 验证安装
docker --version
docker compose version
```

### 步骤 3: 创建项目目录并克隆代码

```bash
# 创建项目根目录
mkdir -p /www/wwwroot
cd /www/wwwroot

# 克隆项目（使用 HTTPS + Token 或 SSH）
git clone https://github.com/paulchen180616/QuanAgent.git
cd QuanAgent
```

### 步骤 4: 配置环境变量

```bash
# 进入 docker 目录
cd docker

# 复制环境变量示例文件
cp .env.example .env

# 编辑环境变量
vim .env
```

**必须修改的关键配置**：

```bash
# ===== 密钥配置 =====
SECRET_KEY=<生成一个强随机密钥>
# 生成方式: openssl rand -base64 42

# ===== 初始管理员密码 =====
INIT_PASSWORD=<设置强密码>

# ===== 数据库配置 =====
DB_USERNAME=postgres
DB_PASSWORD=<设置强数据库密码>
DB_HOST=db_postgres
DB_PORT=5432
DB_DATABASE=quanagent

# ===== Redis 配置 =====
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=<设置强 Redis 密码>

# ===== API 访问地址 =====
CONSOLE_API_URL=http://137.184.191.97
CONSOLE_WEB_URL=http://137.184.191.97
SERVICE_API_URL=http://137.184.191.97
APP_API_URL=http://137.184.191.97
APP_WEB_URL=http://137.184.191.97

# ===== 存储配置（可选，建议使用对象存储）=====
STORAGE_TYPE=local  # 或 s3, azure-blob 等
```

### 步骤 5: 生成安全密钥

```bash
# 生成 SECRET_KEY
openssl rand -base64 42

# 在 .env 文件中更新 SECRET_KEY
sed -i "s/^SECRET_KEY=.*/SECRET_KEY=$(openssl rand -base64 42)/" .env
```

### 步骤 6: 构建前端镜像

由于我们自定义了品牌，需要构建自己的前端镜像：

```bash
cd /www/wwwroot/QuanAgent

# 构建前端镜像
docker build -t quanagent-web:1.10.1 -f web/Dockerfile web/

# 验证镜像
docker images | grep quanagent
```

### 步骤 7: 启动服务

```bash
cd /www/wwwroot/QuanAgent/docker

# 启动所有服务
docker compose up -d

# 查看服务状态
docker compose ps

# 查看日志
docker compose logs -f
```

### 步骤 8: 配置宝塔面板反向代理

1. 登录宝塔面板
2. 网站 -> 添加站点
3. 配置反向代理：

**方案 A: 使用 IP 访问**
```nginx
location / {
    proxy_pass http://127.0.0.1:80;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

**方案 B: 使用域名访问（推荐）**
- 先在宝塔面板中添加网站（如 quanagent.example.com）
- 配置 SSL 证书（Let's Encrypt 免费证书）
- 添加反向代理配置

### 步骤 9: 配置防火墙

```bash
# 使用宝塔面板配置，或使用 ufw
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 22/tcp    # SSH
ufw enable
```

### 步骤 10: 初始化系统

1. 访问 http://137.184.191.97/install
2. 设置管理员账户
3. 登录系统

## 性能优化建议

### 1. 数据持久化

确保数据目录已正确挂载：
```bash
# 查看 docker-compose.yaml 中的 volumes 配置
cd /www/wwwroot/QuanAgent/docker
grep -A 5 "volumes:" docker-compose.yaml
```

### 2. 资源限制

编辑 `docker-compose.yaml` 添加资源限制：
```yaml
services:
  api:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
```

### 3. 日志管理

配置日志轮转：
```yaml
services:
  api:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

## 监控和维护

### 查看服务状态
```bash
cd /www/wwwroot/QuanAgent/docker
docker compose ps
```

### 查看日志
```bash
# 查看所有服务日志
docker compose logs -f

# 查看特定服务日志
docker compose logs -f api
docker compose logs -f web
```

### 重启服务
```bash
# 重启所有服务
docker compose restart

# 重启特定服务
docker compose restart web
docker compose restart api
```

### 更新代码
```bash
cd /www/wwwroot/QuanAgent

# 拉取最新代码
git pull origin main

# 重新构建前端镜像（如果有前端更改）
docker build -t quanagent-web:1.10.1 -f web/Dockerfile web/

# 重启服务
cd docker
docker compose down
docker compose up -d
```

### 备份数据
```bash
# 备份数据库
docker exec docker-db_postgres-1 pg_dump -U postgres quanagent > backup_$(date +%Y%m%d).sql

# 备份 .env 配置
cp /www/wwwroot/QuanAgent/docker/.env /www/backup/.env.backup

# 备份上传的文件
tar -czf storage_backup_$(date +%Y%m%d).tar.gz /www/wwwroot/QuanAgent/docker/volumes/app/storage
```

## 故障排查

### 服务无法启动
```bash
# 查看详细日志
docker compose logs -f

# 检查端口占用
netstat -tulpn | grep -E "80|5001|5432|6379"

# 检查磁盘空间
df -h
```

### 数据库连接失败
```bash
# 进入数据库容器
docker exec -it docker-db_postgres-1 psql -U postgres

# 检查数据库
\l
\q
```

### 内存不足
```bash
# 查看内存使用
free -h

# 查看 Docker 容器资源使用
docker stats
```

## 安全建议

1. **修改默认端口**: 修改 SSH 默认端口（22）
2. **配置防火墙**: 只开放必要的端口
3. **使用 HTTPS**: 配置 SSL 证书
4. **定期更新**: 及时更新系统和 Docker 镜像
5. **强密码策略**: 使用强密码和密钥
6. **备份策略**: 每日自动备份数据库
7. **监控告警**: 配置服务监控和告警

## 常用命令速查

```bash
# 查看运行中的容器
docker ps

# 查看所有容器（包括停止的）
docker ps -a

# 进入容器
docker exec -it <container_name> bash

# 查看容器日志
docker logs -f <container_name>

# 重启所有服务
cd /www/wwwroot/QuanAgent/docker && docker compose restart

# 停止所有服务
docker compose down

# 启动所有服务
docker compose up -d
```

## 性能监控

推荐安装监控工具：
- Portainer（Docker 可视化管理）
- Grafana + Prometheus（性能监控）
- Uptime Kuma（服务可用性监控）

## 联系支持

如遇到问题：
1. 查看本文档的故障排查部分
2. 查看项目 issues：https://github.com/paulchen180616/QuanAgent/issues
3. 查看上游 Dify 文档：https://docs.dify.ai

---
**部署完成后请测试所有功能是否正常工作！**

