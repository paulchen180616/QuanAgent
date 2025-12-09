# QuanAgent 快速部署指南

## 🚀 方式一：一键部署（推荐）

### 1. 连接服务器
```bash
ssh root@137.184.191.97
```

### 2. 下载并运行部署脚本
```bash
# 下载脚本
curl -fsSL https://raw.githubusercontent.com/paulchen180616/QuanAgent/main/deploy.sh -o deploy.sh

# 添加执行权限
chmod +x deploy.sh

# 运行部署脚本
./deploy.sh
```

### 3. 等待部署完成
脚本会自动完成：
- ✅ 安装 Docker 和 Docker Compose
- ✅ 克隆项目代码
- ✅ 配置环境变量
- ✅ 构建前端镜像
- ✅ 启动所有服务

### 4. 访问系统
部署完成后，访问：
```
http://137.184.191.97/install
```

完成初始化设置即可使用！

---

## 📝 方式二：手动部署

### 步骤 1: 安装 Docker
```bash
# 更新系统
apt update && apt upgrade -y

# 安装 Docker
curl -fsSL https://get.docker.com | sh

# 启动 Docker
systemctl start docker
systemctl enable docker
```

### 步骤 2: 克隆项目
```bash
mkdir -p /www/wwwroot
cd /www/wwwroot
git clone https://github.com/paulchen180616/QuanAgent.git
cd QuanAgent
```

### 步骤 3: 配置环境
```bash
cd docker
cp .env.example .env

# 生成安全密钥
SECRET_KEY=$(openssl rand -base64 42)
sed -i "s/^SECRET_KEY=.*/SECRET_KEY=${SECRET_KEY}/" .env

# 编辑其他配置
vim .env
```

### 步骤 4: 构建前端镜像
```bash
cd /www/wwwroot/QuanAgent
docker build -t quanagent-web:1.10.1 -f web/Dockerfile web/
```

### 步骤 5: 启动服务
```bash
cd docker
docker compose up -d
```

### 步骤 6: 访问系统
```
http://137.184.191.97/install
```

---

## 🔧 配置宝塔面板（可选）

如果你想通过域名访问，需要在宝塔面板中配置：

### 1. 添加网站
- 域名: your-domain.com
- 根目录: 任意（不会使用）
- PHP版本: 纯静态

### 2. 配置反向代理
在网站设置 -> 反向代理中添加：

```nginx
location / {
    proxy_pass http://127.0.0.1:80;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

### 3. 配置 SSL（推荐）
- 使用 Let's Encrypt 免费证书
- 启用 HTTPS

---

## 📊 常用命令

### 查看服务状态
```bash
cd /www/wwwroot/QuanAgent/docker
docker compose ps
```

### 查看日志
```bash
# 查看所有日志
docker compose logs -f

# 查看特定服务
docker compose logs -f api
docker compose logs -f web
```

### 重启服务
```bash
docker compose restart
```

### 停止服务
```bash
docker compose down
```

### 启动服务
```bash
docker compose up -d
```

### 更新代码
```bash
cd /www/wwwroot/QuanAgent
git pull
docker build -t quanagent-web:1.10.1 -f web/Dockerfile web/
cd docker
docker compose down
docker compose up -d
```

---

## 🔍 故障排查

### 服务启动失败
```bash
# 查看详细日志
docker compose logs -f

# 检查端口占用
netstat -tulpn | grep -E "80|5001|5432"
```

### 无法访问
1. 检查防火墙是否开放 80 端口
2. 检查服务是否正常运行
3. 检查宝塔面板安全组设置

### 数据库连接失败
```bash
# 进入数据库容器检查
docker exec -it docker-db_postgres-1 psql -U postgres
```

---

## 📞 获取帮助

- 详细文档: [DEPLOYMENT.md](./DEPLOYMENT.md)
- GitHub Issues: https://github.com/paulchen180616/QuanAgent/issues
- Dify 文档: https://docs.dify.ai

---

**祝部署顺利！🎉**

