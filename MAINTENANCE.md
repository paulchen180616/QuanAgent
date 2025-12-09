# QuanAgent 运维手册

## 📋 日常运维

### 查看服务状态

```bash
cd /www/wwwroot/QuanAgent/docker
docker compose ps
```

### 查看日志

```bash
# 实时查看所有服务日志
docker compose logs -f

# 查看特定服务日志
docker compose logs -f api
docker compose logs -f web
docker compose logs -f worker

# 查看最近 100 条日志
docker compose logs --tail=100
```

### 重启服务

```bash
cd /www/wwwroot/QuanAgent/docker

# 重启所有服务
docker compose restart

# 重启特定服务
docker compose restart api web
```

### 停止/启动服务

```bash
# 停止所有服务
docker compose stop

# 启动所有服务
docker compose up -d

# 完全重启（包括数据库）
docker compose down
docker compose up -d
```

## 🔄 更新代码

### 拉取最新代码

```bash
cd /www/wwwroot/QuanAgent

# 拉取代码
git pull origin main

# 重新构建前端镜像（如果前端有更新）
cd docker
docker build -f docker-compose-web.yaml -t quanagent-web:1.10.1 ../web

# 重启服务
docker compose down
docker compose up -d
```

## 💾 备份

### 备份数据库

```bash
# 创建备份目录
mkdir -p /backup/quanagent

# 备份 PostgreSQL 数据库
docker exec docker-db_postgres-1 pg_dump -U postgres dify > /backup/quanagent/dify_$(date +%Y%m%d_%H%M%S).sql

# 验证备份
ls -lh /backup/quanagent/
```

### 备份应用数据

```bash
# 备份 volumes 数据
cd /www/wwwroot/QuanAgent/docker
tar -czf /backup/quanagent/volumes_$(date +%Y%m%d_%H%M%S).tar.gz volumes/

# 备份环境变量
cp .env /backup/quanagent/.env.$(date +%Y%m%d_%H%M%S)
```

### 自动备份脚本

```bash
# 创建自动备份脚本
cat > /root/backup_quanagent.sh << 'EOF'
#!/bin/bash

BACKUP_DIR="/backup/quanagent"
DATE=$(date +%Y%m%d_%H%M%S)

# 创建备份目录
mkdir -p $BACKUP_DIR

# 备份数据库
echo "备份数据库..."
docker exec docker-db_postgres-1 pg_dump -U postgres dify > $BACKUP_DIR/dify_$DATE.sql

# 备份 volumes
echo "备份应用数据..."
cd /www/wwwroot/QuanAgent/docker
tar -czf $BACKUP_DIR/volumes_$DATE.tar.gz volumes/

# 删除 7 天前的备份
echo "清理旧备份..."
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "备份完成！"
EOF

# 添加执行权限
chmod +x /root/backup_quanagent.sh

# 添加到 crontab（每天凌晨 3 点执行）
(crontab -l 2>/dev/null; echo "0 3 * * * /root/backup_quanagent.sh >> /var/log/quanagent_backup.log 2>&1") | crontab -
```

## 🔙 恢复

### 恢复数据库

```bash
# 查看可用备份
ls -lh /backup/quanagent/*.sql

# 恢复数据库
docker exec -i docker-db_postgres-1 psql -U postgres dify < /backup/quanagent/dify_20251209_120000.sql
```

### 恢复应用数据

```bash
cd /www/wwwroot/QuanAgent/docker

# 停止服务
docker compose down

# 恢复 volumes
tar -xzf /backup/quanagent/volumes_20251209_120000.tar.gz -C /www/wwwroot/QuanAgent/docker/

# 恢复权限
chown -R 1001:1001 volumes/app
chown -R 1001:1001 volumes/plugin_daemon
chown -R 70:70 volumes/db
chown -R 999:999 volumes/redis
chown -R 1001:1001 volumes/sandbox

# 启动服务
docker compose up -d
```

## 🧹 清理

### 清理 Docker 资源

```bash
# 查看磁盘使用
docker system df

# 清理未使用的镜像、容器、网络
docker system prune -f

# 清理所有未使用的资源（包括 volumes）
docker system prune -a --volumes
```

### 清理日志

```bash
# 清理 Nginx 日志
cd /www/wwwlogs
gzip agent.quanapps.com_access.log.1
gzip agent.quanapps.com_error.log.1

# 清理 Docker 容器日志
truncate -s 0 /var/lib/docker/containers/*/*-json.log
```

## 📊 监控

### 系统资源监控

```bash
# 实时监控 Docker 资源使用
docker stats

# 查看磁盘使用
df -h

# 查看内存使用
free -h

# 查看 CPU 使用
top
```

### 应用健康检查

```bash
# 检查 Web 服务
curl -I https://agent.quanapps.com/

# 检查 API 服务
curl https://agent.quanapps.com/v1

# 检查数据库连接
docker exec docker-db_postgres-1 psql -U postgres -c "SELECT 1;"

# 检查 Redis
docker exec docker-redis-1 redis-cli ping
```

## 🔐 安全

### 更新 SSL 证书

宝塔面板会自动续期 Let's Encrypt 证书。

手动续期：

```bash
certbot renew

# 测试续期
certbot renew --dry-run
```

### 修改密码

```bash
cd /www/wwwroot/QuanAgent/docker

# 停止服务
docker compose down

# 编辑 .env 文件
vim .env

# 修改以下配置
# POSTGRES_PASSWORD=新密码
# SECRET_KEY=新密钥

# 重新启动
docker compose up -d
```

### 查看访问日志

```bash
# 实时查看 Nginx 访问日志
tail -f /www/wwwlogs/agent.quanapps.com_access.log

# 查看错误日志
tail -f /www/wwwlogs/agent.quanapps.com_error.log

# 统计访问量
awk '{print $1}' /www/wwwlogs/agent.quanapps.com_access.log | sort | uniq -c | sort -rn | head -10
```

## ⚠️ 故障排查

### 服务无法启动

```bash
# 查看服务状态
docker compose ps

# 查看详细日志
docker compose logs service_name

# 检查端口占用
netstat -tlnp | grep -E "3000|5001|5432|6379"

# 检查磁盘空间
df -h
```

### 数据库连接失败

```bash
# 检查数据库容器
docker compose ps db_postgres

# 进入数据库容器
docker exec -it docker-db_postgres-1 psql -U postgres

# 检查数据库
\l

# 检查连接数
SELECT count(*) FROM pg_stat_activity;
```

### 权限错误

```bash
cd /www/wwwroot/QuanAgent/docker

# 重新设置权限
chown -R 1001:1001 volumes/app
chown -R 1001:1001 volumes/plugin_daemon
chown -R 70:70 volumes/db
chown -R 999:999 volumes/redis
chown -R 1001:1001 volumes/sandbox
chmod -R 755 volumes/

# 重启服务
docker compose restart
```

### Nginx 502 错误

```bash
# 检查后端服务是否运行
curl http://127.0.0.1:3000
curl http://127.0.0.1:5001/health

# 检查 Nginx 配置
nginx -t

# 重新加载 Nginx
nginx -s reload

# 查看 Nginx 错误日志
tail -f /www/wwwlogs/agent.quanapps.com_error.log
```

## 📞 获取帮助

- **文档**: [DEPLOYMENT.md](DEPLOYMENT.md)
- **GitHub Issues**: https://github.com/paulchen180616/QuanAgent/issues
- **上游项目**: https://github.com/langgenius/dify

---

**保持系统安全和稳定！** 🔒

