#!/bin/bash

###############################################################################
# QuanAgent 一键部署脚本
# 服务器: Ubuntu 24.04.3 LTS
# 作者: QuanAgent Team
###############################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi
}

# 检查系统版本
check_system() {
    log_info "检查系统版本..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" != "ubuntu" ]; then
            log_warning "此脚本仅在 Ubuntu 上测试过"
        fi
        log_success "系统: $PRETTY_NAME"
    fi
}

# 安装 Docker
install_docker() {
    if command -v docker &> /dev/null; then
        log_success "Docker 已安装: $(docker --version)"
        return
    fi
    
    log_info "安装 Docker..."
    
    # 更新包索引
    apt update
    
    # 安装依赖
    apt install -y ca-certificates curl gnupg lsb-release
    
    # 添加 Docker GPG 密钥
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # 设置 Docker 仓库
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 安装 Docker
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # 启动 Docker
    systemctl start docker
    systemctl enable docker
    
    log_success "Docker 安装完成: $(docker --version)"
}

# 安装 Git
install_git() {
    if command -v git &> /dev/null; then
        log_success "Git 已安装: $(git --version)"
        return
    fi
    
    log_info "安装 Git..."
    apt install -y git
    log_success "Git 安装完成"
}

# 克隆项目
clone_project() {
    PROJECT_DIR="/www/wwwroot/QuanAgent"
    
    if [ -d "$PROJECT_DIR" ]; then
        log_warning "项目目录已存在: $PROJECT_DIR"
        read -p "是否重新克隆？(y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "删除旧目录..."
            rm -rf "$PROJECT_DIR"
        else
            log_info "使用现有目录"
            return
        fi
    fi
    
    log_info "克隆项目..."
    mkdir -p /www/wwwroot
    cd /www/wwwroot
    
    # 使用 HTTPS 克隆
    git clone https://github.com/paulchen180616/QuanAgent.git
    
    log_success "项目克隆完成"
}

# 配置环境变量
configure_env() {
    log_info "配置环境变量..."
    
    cd /www/wwwroot/QuanAgent/docker
    
    if [ ! -f .env ]; then
        cp .env.example .env
        log_success "已创建 .env 文件"
    else
        log_warning ".env 文件已存在，跳过创建"
    fi
    
    # 生成随机密钥
    SECRET_KEY=$(openssl rand -base64 42)
    DB_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-16)
    REDIS_PASSWORD=$(openssl rand -base64 16 | tr -d '/+=' | cut -c1-16)
    
    # 更新配置
    sed -i "s|^SECRET_KEY=.*|SECRET_KEY=${SECRET_KEY}|" .env
    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_PASSWORD}|" .env
    sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=${REDIS_PASSWORD}|" .env
    
    # 获取服务器 IP
    SERVER_IP=$(curl -s ifconfig.me || echo "137.184.191.97")
    
    # 更新 API URLs
    sed -i "s|^CONSOLE_API_URL=.*|CONSOLE_API_URL=http://${SERVER_IP}|" .env
    sed -i "s|^CONSOLE_WEB_URL=.*|CONSOLE_WEB_URL=http://${SERVER_IP}|" .env
    sed -i "s|^SERVICE_API_URL=.*|SERVICE_API_URL=http://${SERVER_IP}|" .env
    sed -i "s|^APP_API_URL=.*|APP_API_URL=http://${SERVER_IP}|" .env
    sed -i "s|^APP_WEB_URL=.*|APP_WEB_URL=http://${SERVER_IP}|" .env
    
    log_success "环境变量配置完成"
    log_info "数据库密码: ${DB_PASSWORD}"
    log_info "Redis 密码: ${REDIS_PASSWORD}"
    log_warning "请妥善保管这些密码！"
    
    # 保存密码到文件
    cat > /root/quanagent_credentials.txt <<EOF
QuanAgent 部署凭据
==================
部署时间: $(date)
服务器IP: ${SERVER_IP}

数据库密码: ${DB_PASSWORD}
Redis密码: ${REDIS_PASSWORD}
Secret Key: ${SECRET_KEY}

访问地址: http://${SERVER_IP}
初始化页面: http://${SERVER_IP}/install
EOF
    
    chmod 600 /root/quanagent_credentials.txt
    log_success "凭据已保存到: /root/quanagent_credentials.txt"
}

# 构建前端镜像
build_frontend() {
    log_info "构建前端镜像..."
    
    cd /www/wwwroot/QuanAgent
    docker build -t quanagent-web:1.10.1 -f web/Dockerfile web/
    
    log_success "前端镜像构建完成"
}

# 启动服务
start_services() {
    log_info "启动服务..."
    
    cd /www/wwwroot/QuanAgent/docker
    docker compose up -d
    
    log_success "服务启动完成"
    
    # 等待服务启动
    log_info "等待服务启动..."
    sleep 10
    
    # 检查服务状态
    log_info "检查服务状态..."
    docker compose ps
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙..."
    
    if command -v ufw &> /dev/null; then
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 22/tcp
        ufw --force enable
        log_success "防火墙配置完成"
    else
        log_warning "未找到 ufw，请手动配置防火墙"
    fi
}

# 显示部署信息
show_deployment_info() {
    SERVER_IP=$(curl -s ifconfig.me || echo "137.184.191.97")
    
    echo ""
    echo "=========================================="
    log_success "QuanAgent 部署完成！"
    echo "=========================================="
    echo ""
    echo "📍 访问地址: http://${SERVER_IP}"
    echo "🔧 初始化页面: http://${SERVER_IP}/install"
    echo ""
    echo "📁 项目目录: /www/wwwroot/QuanAgent"
    echo "📝 凭据文件: /root/quanagent_credentials.txt"
    echo ""
    echo "常用命令:"
    echo "  查看日志: cd /www/wwwroot/QuanAgent/docker && docker compose logs -f"
    echo "  重启服务: cd /www/wwwroot/QuanAgent/docker && docker compose restart"
    echo "  停止服务: cd /www/wwwroot/QuanAgent/docker && docker compose down"
    echo ""
    echo "下一步:"
    echo "  1. 访问 http://${SERVER_IP}/install 完成初始化"
    echo "  2. 创建管理员账户"
    echo "  3. 开始使用 QuanAgent"
    echo ""
    echo "=========================================="
}

# 主函数
main() {
    echo ""
    echo "=========================================="
    echo "   QuanAgent 一键部署脚本"
    echo "=========================================="
    echo ""
    
    check_root
    check_system
    
    log_info "开始部署..."
    
    install_docker
    install_git
    clone_project
    configure_env
    build_frontend
    start_services
    configure_firewall
    
    show_deployment_info
    
    log_success "部署流程完成！"
}

# 运行主函数
main "$@"

