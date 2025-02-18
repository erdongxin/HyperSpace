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
declare -a POINTS_HISTORY    # 积分历史记录数组 
STAGNATION_THRESHOLD=24      # 连续相同积分阈值

# ANSI颜色代码过滤函数
strip_ansi() {
    echo "$1" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g"
}

# 记录日志的函数
log_message() {
    local clean_msg=$(strip_ansi "$1")
    echo -e "$1"
    echo "$(date): $clean_msg" >> $LOG_FILE
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

# 安装本地模型的函数
install_local_model() {
    log_message "${BLUE}正在安装本地模型...${RESET}"
    retry docker exec -i aios-container /app/aios-cli models add hf:afrideva/Tiny-Vicuna-1B-GGUF:tiny-vicuna-1b.q4_k_m.gguf
    log_message "${GREEN}本地模型已成功安装。${RESET}"
}

# 登录
hive_login() {
    local max_retries=10
    local attempt=1

    while [ $attempt -le $max_retries ]; do
        log_message "${CYAN}第 $attempt 次尝试登录Hive...${RESET}"

        docker exec -i $CONTAINER_NAME /app/aios-cli hive import-keys /root/my.pem || {
            ((attempt++))
            sleep 2
            continue
        }

        docker exec -i $CONTAINER_NAME /app/aios-cli hive login || {
            ((attempt++))
            sleep 2
            continue
        }

        docker exec -i $CONTAINER_NAME /app/aios-cli hive select-tier 3 || {
            ((attempt++))
            sleep 2
            continue
        }

        docker exec -i $CONTAINER_NAME /app/aios-cli hive connect || {
            ((attempt++))
            sleep 2
            continue
        }

        log_message "${GREEN}Hive 登录成功！${RESET}"
        return 0
    done

    log_message "${RED}Hive 登录尝试超过 $max_retries 次，放弃。${RESET}"
    return 1
}

# 检查Hive积分的函数
check_hive_points() {
    log_message "${BLUE}正在检查Hive积分...${RESET}"
    local points_output=$(docker exec -i aios-container /app/aios-cli hive points 2>&1)
    
    # 使用更精确的正则表达式匹配 
    if [[ $points_output =~ Points:[[:space:]]+([0-9]+(\.[0-9]+)?) ]]; then 
        local current_points="${BASH_REMATCH[1]}"
        
        # 维护积分历史记录（最多保留24次）
        POINTS_HISTORY+=("$current_points")
        if [ ${#POINTS_HISTORY[@]} -gt $STAGNATION_THRESHOLD ]; then 
            POINTS_HISTORY=("${POINTS_HISTORY[@]:1}") # 移除最旧记录 
        fi 
        
        log_message "${GREEN}当前积分：${CYAN}$current_points 点${RESET}"
        return 0 
    fi 
    
    log_message "${RED}无法获取Hive积分${RESET}"
    return 1 
}

# 获取当前登录的密钥的函数
get_current_signed_in_keys() {
    log_message "${BLUE}正在获取当前登录的密钥...${RESET}"
    docker exec -i aios-container /app/aios-cli hive whoami
}

# 启动函数
start_hyper() {
    while true; do
        log_message "${CYAN}启动脚本流程...${RESET}"
    
        docker rm -f aios-container
        check_and_install_docker
        start_container
        wait_for_container_to_start
        install_local_model
        check_daemon_status
        hive_login
        check_hive_points
        get_current_signed_in_keys
    
        log_message "${GREEN}所有步骤成功完成！${RESET}"
        break
    done
}

# 主流程、启动脚本、监控容器
while true; do
    #启动脚本
    start_hyper
    
    log_message "${BLUE}开始监控容器日志...${RESET}"
    #初始化错误常量
    ERROR_DETECTED=0
    
    #查询积分
    check_hive_points
    # 积分停滞检测，若两小时未改变则触发重启
    if [ ${#POINTS_HISTORY[@]} -eq $STAGNATION_THRESHOLD ]; then 
        unique_points=$(printf "%s\n" "${POINTS_HISTORY[@]}" | sort -u | wc -l)
        
        if [ $unique_points -eq 1 ]; then 
            log_message "${RED}检测到积分连续${STAGNATION_THRESHOLD}次未变化，触发重启...${RESET}"
            ERROR_DETECTED=1 
            POINTS_HISTORY=() # 重置历史记录 
        else 
            log_message "${GREEN}积分变动正常（最近${#POINTS_HISTORY[@]}次记录）${RESET}"
        fi 
    fi

    #检查异常情况
    LOG_TMP_FILE=$(mktemp)
    docker logs --tail 4 $CONTAINER_NAME 2>&1 > "$LOG_TMP_FILE"
    while read -r line; do
        # 过滤颜色代码并记录
        clean_line=$(strip_ansi "$line")
        log_message "${BLUE}容器日志：$clean_line${RESET}"
        
        # 关键错误模式匹配
        if echo "$clean_line" | grep -qE \
            "Last pong received.*Sending reconnect signal|\
Failed to authenticate|\
Failed to connect to Hive|\
already running.*version|\
Checked for auto-update, already running latest version|\
\"message\": \"Internal server error\""
        then
            log_message "${RED}检测到错误模式: $clean_line${RESET}"
            ERROR_DETECTED=1
            break
        fi
    done < "$LOG_TMP_FILE"
    rm -f "$LOG_TMP_FILE"

     #异常重启
    if [ $ERROR_DETECTED -eq 1 ]; then
        log_message "${RED}触发重启流程...${RESET}"

        {
            start_hyper
        } >> $LOG_FILE 2>&1

        log_message "${GREEN}重启流程完成！等待5分钟后继续监控${RESET}"
    else
        log_message "${GREEN}未检测到异常日志${RESET}"
    fi

    log_message "${BLUE}5分钟后再次检查...${RESET}"
    sleep 300
done
