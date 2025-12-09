#!/bin/bash

echo "======== QuanAgent 服务器清理脚本 ========"

# 进入项目目录
cd /www/wwwroot/QuanAgent

# 更新代码
echo "1. 更新代码..."
git pull origin main

# 删除临时 Python 脚本
echo "2. 删除临时脚本..."
rm -f /tmp/disable_nginx.py
rm -f /tmp/add_ports.py
rm -f /tmp/setup_ssl.sh

# 删除 Nginx 配置备份
echo "3. 清理 Nginx 配置备份..."
cd /www/server/panel/vhost/nginx/
rm -f agent.quanapps.com.conf.backup*

# 删除环境变量备份（保留最近的一个）
echo "4. 清理环境变量备份..."
cd /www/wwwroot/QuanAgent/docker
ls -t .env.backup* | tail -n +2 | xargs rm -f 2>/dev/null || true

# 清理 Docker 无用镜像和容器
echo "5. 清理 Docker 资源..."
docker system prune -f

# 显示磁盘使用情况
echo ""
echo "======== 磁盘使用情况 ========"
df -h /www

echo ""
echo "======== Docker 磁盘使用 ========"
docker system df

echo ""
echo "✅ 清理完成！"

