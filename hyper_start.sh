#!/bin/bash

# 定义颜色变量
CYAN='\033[0;36m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RESET='\033[0m'

# 日志文件路径
LOG_FILE="/root/script_progress.log"
CONTAINER_NAME="aios-container"

# 记录日志的函数
log_message() {
    echo -e "$1"
    echo "$(date): $1" >> $LOG_FILE
}

# 重试函数
retry() {
    local n=1
    local delay=10
    while true; do
        "$@" && return 0
        log_message "第 $n 次尝试失败！将在 $delay 秒后重试..."
        sleep $delay
        ((n++))
    done
}

# 检查并安装Docker的函数
check_and_install_docker() {
    if ! command -v docker &> /dev/null; then
        log_message "${RED}未找到Docker。正在安装Docker...${RESET}"
        retry apt-get update -y
        retry apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        retry apt update -y
        retry apt install -y docker-ce
        systemctl start docker
        systemctl enable docker
        log_message "${GREEN}Docker已安装并启动。${RESET}"
    else
        log_message "${GREEN}Docker已安装。${RESET}"
    fi
}

# 启动Docker容器的函数
start_container() {
    log_message "${BLUE}正在启动Docker容器...${RESET}"
    retry docker run -d --name aios-container --restart unless-stopped -v /root:/root kartikhyper/aios /app/aios-cli start
    log_message "${GREEN}Docker容器已启动。${RESET}"
}

# 等待容器初始化的函数
wait_for_container_to_start() {
    log_message "${CYAN}正在等待容器初始化...${RESET}"
    sleep 30
}

# 检查守护进程状态的函数
check_daemon_status() {
    log_message "${BLUE}正在检查容器内的守护进程状态...${RESET}"
    docker exec -i aios-container /app/aios-cli status
    if [[ $? -ne 0 ]]; then
        log_message "${RED}守护进程未运行，正在重启...${RESET}"
        docker exec -i aios-container /app/aios-cli kill
        sleep 2
        docker exec -i aios-container /app/aios-cli start
        log_message "${GREEN}守护进程已重启。${RESET}"
    else
        log_message "${GREEN}守护进程正在运行。${RESET}"
    fi
}

# 安装本地模型的函数（增加重试逻辑）
install_local_model() {
    log_message "${BLUE}正在安装本地模型...${RESET}"
    retry docker exec -i aios-container /app/aios-cli models add hf:afrideva/Tiny-Vicuna-1B-GGUF:tiny-vicuna-1b.q4_k_m.gguf
    log_message "${GREEN}本地模型已成功安装。${RESET}"
}

hive_login() {

    local max_retries=5  # 最大重试次数
    local attempt=1      # 当前尝试次数

    while [ $attempt -le $max_retries ]; do
        log_message "${CYAN}第 $attempt 次尝试登录Hive...${RESET}"

        # 步骤 1: 导入密钥
        docker exec -i $CONTAINER_NAME /app/aios-cli hive import-keys /root/my.pem
        if [ $? -ne 0 ]; then
            log_message "${RED}第 $attempt 次尝试失败: 导入密钥失败。${RESET}"
            ((attempt++))
            sleep 2  # 等待 2 秒后重试
            continue
        fi

        # 步骤 2: Hive 登录
        docker exec -i $CONTAINER_NAME /app/aios-cli hive login
        if [ $? -ne 0 ]; then
            log_message "${RED}第 $attempt 次尝试失败: Hive 登录失败。${RESET}"
            ((attempt++))
            sleep 2  # 等待 2 秒后重试
            continue
        fi

        # 步骤 3: 选择 tier 3
        docker exec -i $CONTAINER_NAME /app/aios-cli hive select-tier 3
        if [ $? -ne 0 ]; then
            log_message "${RED}第 $attempt 次尝试失败: 选择 tier 3 失败。${RESET}"
            ((attempt++))
            sleep 2  # 等待 2 秒后重试
            continue
        fi

        # 步骤 4: Hive 连接
        docker exec -i $CONTAINER_NAME /app/aios-cli hive connect
        if [ $? -ne 0 ]; then
            log_message "${RED}第 $attempt 次尝试失败: Hive 连接失败。${RESET}"
            ((attempt++))
            sleep 2  # 等待 2 秒后重试
            continue
        fi

        log_message "${GREEN}Hive 登录成功！${RESET}"
        return 0  # 全部步骤成功，退出函数
    done

    log_message "${RED}Hive 登录尝试超过 $max_retries 次，放弃。${RESET}"
    return 1  # 超过重试次数，返回失败状态
}


# 检查Hive积分的函数
check_hive_points() {
    log_message "${BLUE}正在检查Hive积分...${RESET}"
    docker exec -i aios-container /app/aios-cli hive points || log_message "${RED}无法获取Hive积分。${RESET}"
    log_message "${GREEN}Hive积分检查完成。${RESET}"
}

# 获取当前登录的密钥的函数
get_current_signed_in_keys() {
    log_message "${BLUE}正在获取当前登录的密钥...${RESET}"
    docker exec -i aios-container /app/aios-cli hive whoami
}

# 清理包列表的函数
cleanup_package_lists() {
    log_message "${BLUE}正在清理包列表...${RESET}"
    sudo rm -rf /var/lib/apt/lists/*
}

# 主脚本流程
while true; do
    log_message "${CYAN}启动脚本流程...${RESET}"

    # 删除原有容器
    docker rm -f aios-container
    
    # 检查和安装Docker
    check_and_install_docker || continue

    # 启动容器
    start_container || continue

    # 等待容器初始化
    wait_for_container_to_start || continue

    # 安装本地模型
    install_local_model || continue

    # 检查守护进程
    check_daemon_status || continue

    # 登录Hive
    hive_login || continue

    # 检查Hive积分
    check_hive_points || continue

    # 获取当前登录密钥
    get_current_signed_in_keys || continue

    log_message "${GREEN}所有步骤成功完成！${RESET}"
    break
done


# 监控容器日志并触发操作
while true; do
    log_message "${BLUE}开始监控容器日志...${RESET}"

    # 获取最新日志并逐行读取（只读取最新10条)
    docker logs --tail 10 aios-container | while read -r line; do
        log_message "${BLUE} 容器日志：$line ${RESET}"
        
        # 只在检测到异常时触发重启
        if echo "$line" | grep -qE "Last pong received.*Sending reconnect signal|Failed to authenticate|Failed to connect to Hive|already running|Checked for auto-update.*already running latest version|\"message\": \"Internal server error\"" ; then

            log_message "${BLUE}检测到错误，正在重新连接...${RESET}"

            # 删除原有容器
            docker rm -f aios-container
            
            # 检查和安装Docker
            check_and_install_docker || continue
        
            # 启动容器
            start_container || continue
        
            # 等待容器初始化
            wait_for_container_to_start || continue
        
            # 安装本地模型
            install_local_model || continue
        
            # 检查守护进程
            check_daemon_status || continue
        
            # 登录Hive
            hive_login || continue
        
            # 检查Hive积分
            check_hive_points || continue
        
            # 获取当前登录密钥
            get_current_signed_in_keys || continue
        
            log_message "${GREEN}所有步骤成功完成！${RESET}"

            # 记录服务已重启
            log_message "${BLUE}服务已重启${RESET}"

            # 退出当前循环，等待下次 5 分钟检查
            break
        fi
    done

    # 休眠 5 分钟后再次检测
    log_message "${BLUE}容器日志已检查，5分钟后再次检查...${RESET}"
    sleep 300
done

