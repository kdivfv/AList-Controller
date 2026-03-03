#!/data/data/com.termux/files/usr/bin/bash

# ===== 配置 =====
ALIST_DIR="$(pwd)"
ALIST_BIN="./alist"
ALIST_PID_FILE="$ALIST_DIR/.alist_service.pid"
LOG_FILE="$ALIST_DIR/alist_service.log"
DATA_DIR="$ALIST_DIR/data"
ALIST_CONFIG_FILE="$DATA_DIR/config.json"
FIRST_START_FILE="$ALIST_DIR/first_start.info"
IP_CACHE_FILE="$ALIST_DIR/.ip_cache.txt"
QR_TEMP_DIR="$ALIST_DIR/.qr_temp"

# ===== 颜色定义 =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'  
BLUE='\033[0;34m'    
PURPLE='\033[0;35m'  
CYAN='\033[0;36m'    
WHITE='\033[0;37m'   
NC='\033[0m'

# ===== 辅助函数 =====
get_alist_version() {
    if [ -f "$ALIST_BIN" ] && [ -x "$ALIST_BIN" ]; then
        "$ALIST_BIN" version 2>/dev/null | head -1
    else
        echo "未安装"
    fi
}

# ===== 获取第一个可用的局域网IP =====
get_first_lan_ip() {
    local ip=""
    
    # 使用ip命令获取第一个非本地IPv4地址
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1 2>/dev/null)
    fi
    
    # 如果失败，使用ifconfig
    if [ -z "$ip" ] && command -v ifconfig >/dev/null 2>&1; then
        ip=$(ifconfig 2>/dev/null | grep -oE 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -oE '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1 2>/dev/null)
    fi
    
    # 如果都没有，返回localhost
    if [ -z "$ip" ]; then
        ip="127.0.0.1"
    fi
    
    echo "$ip"
}

# ===== 生成二维码 =====
generate_qrcode() {
    local url="$1"
    local output_file="$2"
    
    mkdir -p "$QR_TEMP_DIR" 2>/dev/null
    
    # 修改点：同时检查 qrencode 和 libqrencode
    if command -v qrencode >/dev/null 2>&1 || [ -f "$PREFIX/lib/libqrencode.so" ]; then
        # 如果有 qrencode 命令就用命令，否则尝试用库（但通常还是需要命令）
        if command -v qrencode >/dev/null 2>&1; then
            qrencode -o "$output_file" -s 6 -m 2 "$url" 2>/dev/null
            return $?
        fi
    fi
    
    # Python 备用方案保持不变
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import qrcode
try:
    img = qrcode.make('$url')
    img.save('$output_file')
except:
    pass
" 2>/dev/null
        return $?
    fi
    
    return 1
}
# ===== 显示二维码 =====
display_qrcode() {
    local url="$1"
    local qr_file="$QR_TEMP_DIR/qrcode_$$.png"
    
    echo ""
    echo  "${CYAN}📱 扫描二维码访问:${NC}"
    echo  "${WHITE}════════════════════════════════════${NC}"
    echo  "${WHITE}$url${NC}"
    echo  "${WHITE}════════════════════════════════════${NC}"
    
    if generate_qrcode "$url" "$qr_file"; then
        if command -v termux-media-scan >/dev/null 2>&1; then
            termux-media-scan "$qr_file" >/dev/null 2>&1
            echo  "${GREEN}✅ 二维码已生成${NC}"
        fi
        
        if command -v qrencode >/dev/null 2>&1; then
            echo ""
            qrencode -t ANSI256 "$url" 2>/dev/null
        fi
    else
        echo  "${YELLOW}⚠ 生成二维码失败，请选择菜单11安装所需环境${NC}"
    fi
    
    echo  "${WHITE}════════════════════════════════════${NC}"
    
    ls -t "$QR_TEMP_DIR"/qrcode_*.png 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null
}

# ===== 安装二维码环境 =====
install_qr_env() {
    echo  "${CYAN}====== 安装二维码生成环境 ======${NC}"
    echo ""
    echo  "${YELLOW}将安装: libqrencode 和 python-qrcode${NC}"
    echo -n "确定要安装吗？(y/N): "
    read -r confirm 2>/dev/null
    
    case "$confirm" in
        [Yy]*)
            echo  "${YELLOW}🔄 正在安装 libqrencode...${NC}"
            pkg update -y
            pkg install -y libqrencode
            
            echo  "${YELLOW}🔄 正在安装 Python 和 qrcode 库...${NC}"
            pkg install -y python python-pip
            python -m pip install qrcode
            
            echo  "${GREEN}✅ 安装完成${NC}"
            echo  "${YELLOW}📝 说明: libqrencode 是底层库，Python 将用于生成二维码${NC}"
            ;;
        *)
            echo  "${GREEN}✅ 已取消安装${NC}"
            ;;
    esac
    
    wait_for_enter
}
# ===== 等待输入函数 =====
wait_for_enter() {
    echo -n "按回车键继续..."
    if command -v read >/dev/null 2>&1; then
        read dummy
    else
        sleep 2
    fi
}

# ===== 退出自动清理 =====
cleanup_self_only() {
    echo  "${YELLOW}[清理] ...${NC}"
    rm -f "$QR_TEMP_DIR"/qrcode_$$.png 2>/dev/null
    rmdir "$QR_TEMP_DIR" 2>/dev/null
    
    if command -v pkill >/dev/null 2>&1; then
        pkill -9 -P $$ 2>/dev/null
    fi
    jobs -p | xargs kill -9 2>/dev/null 2>/dev/null
    echo  "${GREEN}[清理] ✅ 完成${NC}"
    exit 0
}
trap cleanup_self_only EXIT INT TERM HUP

# ===== Alist进程检查 =====
check_alist_process() {
    if [ -f "$ALIST_PID_FILE" ]; then
        local pid=$(cat "$ALIST_PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
            echo "$pid"
            return 0
        fi
        rm -f "$ALIST_PID_FILE"
    fi
    
    local pid=$(pgrep -f "alist server" 2>/dev/null | head -1)
    if [ -n "$pid" ]; then
        echo "$pid"
        return 0
    fi
    
    return 1
}

# ===== Alist智能下载函数 =====
android_download_alist() {
    echo  "${CYAN}====== Alist智能下载安装 ======${NC}"
    echo ""
    
    if [ -f "$ALIST_BIN" ] && [ -x "$ALIST_BIN" ]; then
        echo  "${YELLOW}⚠ Alist已经安装${NC}"
        CURRENT_VER=$("$ALIST_BIN" version 2>/dev/null | head -1 || echo "未知")
        echo  "当前版本: $CURRENT_VER"
        echo -n "是否重新安装？(y/N): "
        read -r reinstall 2>/dev/null
        case "$reinstall" in
            [Yy]*)
                echo  "${YELLOW}🔄 开始重新安装...${NC}"
                stop_alist_service >/dev/null 2>&1
                ;;
            *)
                echo  "${GREEN}✅ 已取消重新安装${NC}"
                wait_for_enter
                return 0
                ;;
        esac
    fi
    
    ARCH_FULL=$(uname -m)
    echo  "${CYAN}[1/4] 检测设备架构: $ARCH_FULL${NC}"
    
    case "$ARCH_FULL" in
        "aarch64"|"arm64") ARCH_PATTERN="arm64" ;;
        "armv7l"|"armv7") ARCH_PATTERN="armv7" ;;
        "x86_64") ARCH_PATTERN="amd64" ;;
        "i686"|"i386") ARCH_PATTERN="386" ;;
        *) ARCH_PATTERN="$ARCH_FULL" ;;
    esac
    
    echo  "${CYAN}[2/4] 获取Alist最新发布信息...${NC}"
    USER_AGENT="Mozilla/5.0 (Linux; Android 13; SM-S901U) AppleWebKit/537.36"
    
    API_RESPONSE=$(curl -s -L -A "$USER_AGENT" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/alist-org/alist/releases/latest")
    
    LATEST_TAG=$(echo "$API_RESPONSE" | grep '"tag_name"' | sed 's/.*"tag_name": "\([^"]*\)".*/\1/')
    
    if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" = "null" ]; then
        LATEST_TAG="latest"
    fi
    
    echo  "${CYAN}[3/4] 搜索匹配的下载链接...${NC}"
    
    MATCHED_URL=$(echo "$API_RESPONSE" | grep -o '"browser_download_url":"[^"]*"' | \
      grep -i "android.*$ARCH_PATTERN\|$ARCH_PATTERN.*android" | \
      head -1 | cut -d'"' -f4)
    
    if [ -z "$MATCHED_URL" ]; then
        RELEASE_PAGE=$(curl -s -L -A "$USER_AGENT" \
          "https://github.com/alist-org/alist/releases/expanded_assets/$LATEST_TAG")
        
        MATCHED_URL=$(echo "$RELEASE_PAGE" | grep -o 'href="[^"]*\.tar\.gz"' | \
          grep -i "android.*$ARCH_PATTERN\|$ARCH_PATTERN.*android" | \
          head -1 | sed 's/href="//;s/"//')
        
        if [ -n "$MATCHED_URL" ]; then
            case "$MATCHED_URL" in
                http*) ;;
                *) MATCHED_URL="https://github.com$MATCHED_URL" ;;
            esac
        fi
    fi
    
    if [ -n "$MATCHED_URL" ]; then
        DOWNLOAD_URL="$MATCHED_URL"
    else
        echo  "${RED}❌ 未找到匹配的AList文件${NC}"
        wait_for_enter
        return 1
    fi
    
    echo  "${CYAN}[4/4] 开始下载...${NC}"
    FILE_NAME=$(basename "$DOWNLOAD_URL")
    
    if wget --user-agent="$USER_AGENT" -O "$FILE_NAME" --show-progress --timeout=30 "$DOWNLOAD_URL"; then
        if [ -f "$FILE_NAME" ]; then
            tar -xzf "$FILE_NAME" 2>/dev/null
            
            if [ -f "alist" ]; then
                chmod +x alist
                echo  "${GREEN}✅ 安装完成！${NC}"
                rm -f "$FILE_NAME"
            else
                FOUND=$(find . -maxdepth 2 -name "alist" -type f | head -1)
                if [ -n "$FOUND" ]; then
                    cp "$FOUND" .
                    chmod +x alist
                    echo  "${GREEN}✅ 安装完成！${NC}"
                    rm -f "$FILE_NAME"
                fi
            fi
        fi
    fi
    
    wait_for_enter
}

# ===== 检查是否为首次启动 =====
check_first_start() {
    if [ ! -f "$ALIST_CONFIG_FILE" ]; then
        return 0
    fi
    return 1
}

# ===== 从日志中提取密码 =====
extract_password_from_log() {
    local log_file="$1"
    local password=""
    
    if [ -f "$log_file" ]; then
        password=$(grep -i "password" "$log_file" | grep -v "admin\|root" | head -1 | sed 's/.*password.*: //i' 2>/dev/null)
    fi
    
    echo "$password"
}

# ===== 密码修改函数 =====
change_alist_password() {
    echo  "${CYAN}====== Alist密码修改 ======${NC}"
    
    if [ ! -f "$ALIST_BIN" ]; then
        echo  "${RED}❌ 错误：找不到 $ALIST_BIN${NC}"
        wait_for_enter
        return 1
    fi
    
    echo -n "输入新密码: "
    read -r new_password 2>/dev/null
    
    if [ -z "$new_password" ]; then
        echo  "${RED}❌ 密码不能为空${NC}"
        wait_for_enter
        return 1
    fi
    
    echo -n "确认新密码: "
    read -r confirm_password 2>/dev/null
    
    if [ "$new_password" != "$confirm_password" ]; then
        echo  "${RED}❌ 两次输入的密码不一致${NC}"
        wait_for_enter
        return 1
    fi
    
    cd "$ALIST_DIR"
    "$ALIST_BIN" admin set "$new_password"
    
    echo ""
    if [ $? -eq 0 ]; then
        echo  "${GREEN}✅ 密码修改成功！${NC}"
    else
        echo  "${RED}❌ 密码修改失败${NC}"
    fi
    
    wait_for_enter
}

# ===== 启动Alist服务 =====
start_alist_service() {
    echo  "${CYAN}[Alist] 启动服务...${NC}"
    
    if check_alist_process >/dev/null; then
        local pid=$(check_alist_process)
        echo  "${YELLOW}⚠ Alist已在运行 (PID: $pid)${NC}"
        echo ""
        
        local lan_ip=$(get_first_lan_ip)
        echo  "${YELLOW}🌐 访问地址: http://$lan_ip:5244${NC}"
        display_qrcode "http://$lan_ip:5244"
        
        wait_for_enter
        return 0
    fi
    
    if [ ! -f "$ALIST_BIN" ]; then
        echo  "${RED}❌ 错误：找不到 $ALIST_BIN${NC}"
        wait_for_enter
        return 1
    fi
    
    [ ! -x "$ALIST_BIN" ] && chmod +x "$ALIST_BIN"
    
    local is_first_start=0
    check_first_start && is_first_start=1
    
    echo  "${CYAN}🔄 启动Alist服务...${NC}"
    cd "$ALIST_DIR"
    "$ALIST_BIN" server > "$LOG_FILE" 2>&1 &
    local alist_pid=$!
    
    echo "$alist_pid" > "$ALIST_PID_FILE"
    
    echo  "${YELLOW}⏳ 等待Alist启动...${NC}"
    sleep 3
    
    if ! ps -p "$alist_pid" >/dev/null 2>&1; then
        echo  "${RED}❌ 启动失败！${NC}"
        wait_for_enter
        return 1
    fi
    
    echo  "${GREEN}✅ 启动完成 (PID: $alist_pid)${NC}"
    
    local lan_ip=$(get_first_lan_ip)
    
    if [ $is_first_start -eq 1 ]; then
        sleep 5
        local password=$(extract_password_from_log "$LOG_FILE")
        
        if [ -n "$password" ]; then
            echo ""
            echo  "${WHITE}════════════════════════════════════════════${NC}"
            echo  "${CYAN}           Alist首次启动成功${NC}"
            echo  "${WHITE}════════════════════════════════════════════${NC}"
            echo  "  ${GREEN}✅ 用户名: admin${NC}"
            echo  "  ${GREEN}✅ 密码: $password${NC}"
            echo ""
            
            echo  "${YELLOW}🌐 访问地址: http://$lan_ip:5244${NC}"
            display_qrcode "http://$lan_ip:5244"
            echo  "${WHITE}════════════════════════════════════════════${NC}"
            
            echo -n "请保存信息后按回车键继续..."
            wait_for_enter
        fi
    else
        echo ""
        echo  "${YELLOW}🌐 访问地址: http://$lan_ip:5244${NC}"
        display_qrcode "http://$lan_ip:5244"
        wait_for_enter
    fi
}

# ===== 停止Alist服务 =====
stop_alist_service() {
    echo  "${CYAN}[Alist] 停止服务...${NC}"
    
    local pid=$(check_alist_process)
    if [ -z "$pid" ]; then
        echo  "${YELLOW}ℹ Alist未运行${NC}"
        wait_for_enter
        return 0
    fi
    
    kill "$pid" 2>/dev/null
    sleep 2
    
    if ps -p "$pid" >/dev/null 2>&1; then
        kill -9 "$pid" 2>/dev/null
    fi
    
    rm -f "$ALIST_PID_FILE"
    
    if check_alist_process >/dev/null; then
        echo  "${RED}❌ 停止失败${NC}"
    else
        echo  "${GREEN}✅ 已停止${NC}"
    fi
    
    wait_for_enter
}

# ===== 显示登录信息 =====
show_password_info() {
    echo  "${CYAN}====== Alist登录信息 ======${NC}"
    
    if check_alist_process >/dev/null; then
        local lan_ip=$(get_first_lan_ip)
        echo  "${GREEN}✅ 用户名: admin${NC}"
        echo  "${YELLOW}🌐 访问地址: http://$lan_ip:5244${NC}"
        display_qrcode "http://$lan_ip:5244"
    else
        echo  "${RED}⚠ Alist服务未运行${NC}"
        local lan_ip=$(get_first_lan_ip)
        echo  "${YELLOW}📋 上次地址: http://$lan_ip:5244${NC}"
    fi
    
    wait_for_enter
}

# ===== 卸载Alist =====
uninstall_alist() {
    echo  "${RED}====== Alist卸载程序 ======${NC}"
    echo ""
    echo  "${RED}⚠ 警告：这将删除Alist所有文件！${NC}"
    echo ""
    echo -n "确定要卸载Alist吗？(y/N): "
    read -r confirm 2>/dev/null
    
    case "$confirm" in
        [Yy]*)
            stop_alist_service >/dev/null 2>&1
            rm -f "$ALIST_BIN"
            rm -rf "$DATA_DIR"
            rm -f "$LOG_FILE"
            rm -f "$ALIST_PID_FILE"
            rm -f "$FIRST_START_FILE"
            rm -f "$IP_CACHE_FILE"
            rm -rf "$QR_TEMP_DIR"
            rm -f alist-*.tar.gz 2>/dev/null
            echo  "${GREEN}✅ Alist卸载完成${NC}"
            ;;
        *)
            echo  "${GREEN}✅ 已取消卸载${NC}"
            ;;
    esac
    
    wait_for_enter
}

# ===== 显示系统信息 =====
show_system_info() {
    echo  "${CYAN}====== 系统信息 ======${NC}"
    echo  "操作系统: $(uname -o 2>/dev/null || uname -s)"
    echo  "内核版本: $(uname -r)"
    echo  "系统架构: $(uname -m)"
    echo  "局域网IP: $(get_first_lan_ip)"
    
    wait_for_enter
}

# ===== 显示状态详情 =====
show_status_detail() {
    echo  "${CYAN}====== Alist状态详情 ======${NC}"
    
    local pid=$(check_alist_process)
    if [ -n "$pid" ]; then
        echo  "${GREEN}🟢 运行状态: 运行中 (PID: $pid)${NC}"
        local lan_ip=$(get_first_lan_ip)
        echo  "${YELLOW}🌐 访问地址: http://$lan_ip:5244${NC}"
        display_qrcode "http://$lan_ip:5244"
    else
        echo  "${RED}🔴 运行状态: 已停止${NC}"
        local lan_ip=$(get_first_lan_ip)
        echo  "${YELLOW}📋 上次地址: http://$lan_ip:5244${NC}"
    fi
    
    wait_for_enter
}

# ===== 查看日志 =====
show_log() {
    echo  "${CYAN}====== Alist服务日志 ======${NC}"
    
    if [ -f "$LOG_FILE" ]; then
        echo  "${YELLOW}最近20行日志:${NC}"
        echo  "${WHITE}----------------------------------------${NC}"
        tail -20 "$LOG_FILE"
        echo  "${WHITE}----------------------------------------${NC}"
    else
        echo  "${YELLOW}日志文件不存在${NC}"
    fi
    
    wait_for_enter
}

# ===== 主菜单 =====
show_menu() {
    clear
    echo ""
    echo  "               ${CYAN}🔧 Alist 管理器${NC}"
    echo  "${WHITE}════════════════════════════════════════════${NC}"
    
    local pid=$(check_alist_process)
    if [ -n "$pid" ]; then
        echo  "🟢 ${GREEN}运行状态: 运行中 (PID: $pid)${NC}"
        local lan_ip=$(get_first_lan_ip)
        echo  "🌐 ${BLUE}访问地址: http://$lan_ip:5244${NC}"
    else
        echo  "🔴 ${RED}运行状态: 已停止${NC}"
        local lan_ip=$(get_first_lan_ip)
        echo  "📋 ${YELLOW}上次地址: http://$lan_ip:5244${NC}"
    fi
    
    echo  "📦 ${YELLOW}Alist版本: $(get_alist_version)${NC}"
    echo  "${WHITE}════════════════════════════════════════════${NC}"
    echo  "              ${CYAN}1.${NC} 🚀 启动Alist服务"
    echo  "              ${CYAN}2.${NC} 🛑 停止Alist服务"
    echo  "              ${CYAN}3.${NC} 🔄 重启Alist服务"
    echo  "              ${CYAN}4.${NC} 🔑 修改管理员密码"
    echo  "              ${CYAN}5.${NC} 🔐 查看登录地址信息"
    echo  "              ${CYAN}6.${NC} 📋 查看服务日志"
    echo  "              ${CYAN}7.${NC} 📊 查看状态详情"
    echo  "              ${CYAN}8.${NC} 📦 安装/更新Alist"
    echo  "              ${CYAN}9.${NC} 💻 查看系统信息"
    echo  "              ${CYAN}10.${NC} 🗑️  卸载Alist"
    echo  "              ${CYAN}11.${NC} 📱 安装二维码环境"
    echo ""
    echo  "              ${CYAN}0.${NC} ❌ 退出"
    echo  "${WHITE}════════════════════════════════════════════${NC}"
    echo ""
    echo -n "请选择 (0-11): "
}

# ===== 主程序 =====
main() {
    mkdir -p "$QR_TEMP_DIR" 2>/dev/null
    
    while true; do
        show_menu
        read -r choice 2>/dev/null
        
        case "$choice" in
            1) start_alist_service ;;
            2) stop_alist_service ;;
            3) stop_alist_service; sleep 2; start_alist_service ;;
            4) change_alist_password ;;
            5) show_password_info ;;
            6) show_log ;;
            7) show_status_detail ;;
            8) android_download_alist ;;
            9) show_system_info ;;
            10) uninstall_alist ;;
            11) install_qr_env ;;
            0) echo  "${CYAN}👋 退出...${NC}"; exit 0 ;;
            *) echo  "${RED}❌ 无效选择${NC}"; sleep 1 ;;
        esac
    done
}

main