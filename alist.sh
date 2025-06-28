#!/bin/bash
###############################################################################
#
# Alist Manager Script
#
# Version: 1.0.0
# Last Updated: 2024-12-24
#
###############################################################################

# 错误处理函数
handle_error() {
    local exit_code=$1
    local error_msg=$2
    echo -e "${RED_COLOR}错误：${error_msg}${RES}"
    exit ${exit_code}
}

# 颜色配置
RED_COLOR='\e[1;31m'
GREEN_COLOR='\e[1;32m'
YELLOW_COLOR='\e[1;33m'
RES='\e[0m'

# 检查 curl
if ! command -v curl >/dev/null 2>&1; then
    handle_error 1 "未找到 curl 命令，请先安装"
fi

# 获取平台架构
if command -v arch >/dev/null 2>&1; then
  platform=$(arch)
else
  platform=$(uname -m)
fi

ARCH="UNKNOWN"
if [ "$platform" = "x86_64" ]; then
  ARCH=amd64
elif [ "$platform" = "aarch64" ]; then
  ARCH=arm64
fi

# 检查权限
if [ "$(id -u)" != "0" ]; then
  case "$1" in
    install|update|uninstall)
      echo -e "\n${RED_COLOR}错误：请使用 root 权限运行此命令！${RES}\n"
      echo -e "提示：使用 ${GREEN_COLOR}sudo $0 $1${RES} 重试\n"
      exit 1
      ;;
  esac
elif [ "$ARCH" == "UNKNOWN" ]; then
  echo -e "\n${RED_COLOR}出错了${RES}，仅支持 x86_64 和 arm64 平台。\n"
  exit 1
elif ! command -v systemctl >/dev/null 2>&1; then
  echo -e "\n${RED_COLOR}出错了${RES}，无法找到 systemd。\n"
  exit 1
fi

# 路径相关
GET_INSTALLED_PATH() {
    if [ -f "/etc/systemd/system/alist.service" ]; then
        installed_path=$(grep "WorkingDirectory=" /etc/systemd/system/alist.service | cut -d'=' -f2)
        if [ -f "$installed_path/alist" ]; then
            echo "$installed_path"
            return 0
        fi
    fi
    echo "/opt/alist"
}

# 安装路径设置
if [ ! -n "$2" ]; then
    INSTALL_PATH='/opt/alist'
else
    INSTALL_PATH=${2%/}
    [[ $INSTALL_PATH == */alist ]] || INSTALL_PATH="$INSTALL_PATH/alist"
    parent_dir=$(dirname "$INSTALL_PATH")
    [ -d "$parent_dir" ] || mkdir -p "$parent_dir" || handle_error 1 "无法创建目录 $parent_dir"
    [ -w "$parent_dir" ] || handle_error 1 "目录 $parent_dir 没有写入权限"
fi

if [ "$1" = "update" ] || [ "$1" = "uninstall" ]; then
    INSTALL_PATH=$(GET_INSTALLED_PATH)
fi

# 全局变量
ADMIN_USER=""
ADMIN_PASS=""

# 下载函数
download_file() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_count=0
    local wait_time=5

    while [ $retry_count -lt $max_retries ]; do
        if curl -L --connect-timeout 10 --retry 3 --retry-delay 3 "$url" -o "$output"; then
            [ -f "$output" ] && [ -s "$output" ] && return 0
        fi
        retry_count=$((retry_count + 1))
        [ $retry_count -lt $max_retries ] && {
            echo -e "${YELLOW_COLOR}下载失败，第 $((retry_count)) 次重试中...${RES}"
            sleep $wait_time
            wait_time=$((wait_time + 5))
        }
    done
    echo -e "${RED_COLOR}下载失败，已重试 $max_retries 次${RES}"
    return 1
}

INSTALL() {
    local GH_PROXY=""
    local GH_DOWNLOAD_URL=""
    echo -e "${GREEN_COLOR}是否使用 GitHub 代理？（默认无代理）${RES}"
    read -p "请输入代理地址或直接按回车继续: " proxy_input
    if [ -n "$proxy_input" ]; then
        GH_PROXY="$proxy_input"
        GH_DOWNLOAD_URL="${GH_PROXY}https://github.com/alist-org/alist/releases/latest/download"
    else
        GH_DOWNLOAD_URL="https://github.com/alist-org/alist/releases/latest/download"
    fi

    echo -e "${GREEN_COLOR}下载 Alist 中...${RES}"
    download_file "${GH_DOWNLOAD_URL}/alist-linux-musl-$ARCH.tar.gz" "/tmp/alist.tar.gz" || exit 1

    mkdir -p "$INSTALL_PATH"
    tar zxf /tmp/alist.tar.gz -C "$INSTALL_PATH" || handle_error 1 "解压失败"

    cd "$INSTALL_PATH"
    ACCOUNT_INFO=$("$INSTALL_PATH/alist" admin random 2>&1)
    ADMIN_USER=$(echo "$ACCOUNT_INFO" | grep "username:" | awk -F':' '{print $2}' | xargs)
    ADMIN_PASS=$(echo "$ACCOUNT_INFO" | grep "password:" | awk -F':' '{print $2}' | xargs)

    rm -f /tmp/alist.tar.gz
}

UPDATE() {
    local GH_PROXY=""
    local GH_DOWNLOAD_URL=""
    echo -e "${GREEN_COLOR}是否使用 GitHub 代理？（默认无代理）${RES}"
    read -p "请输入代理地址或直接按回车继续: " proxy_input
    if [ -n "$proxy_input" ]; then
        GH_PROXY="$proxy_input"
        GH_DOWNLOAD_URL="${GH_PROXY}https://github.com/alist-org/alist/releases/latest/download"
    else
        GH_DOWNLOAD_URL="https://github.com/alist-org/alist/releases/latest/download"
    fi

    systemctl stop alist
    cp "$INSTALL_PATH/alist" /tmp/alist.bak

    echo -e "${GREEN_COLOR}下载 Alist 中...${RES}"
    download_file "${GH_DOWNLOAD_URL}/alist-linux-musl-$ARCH.tar.gz" "/tmp/alist.tar.gz" || {
        echo -e "${RED_COLOR}下载失败，恢复备份...${RES}"
        mv /tmp/alist.bak "$INSTALL_PATH/alist"
        systemctl start alist
        exit 1
    }

    tar zxf /tmp/alist.tar.gz -C "$INSTALL_PATH" || {
        echo -e "${RED_COLOR}解压失败，恢复备份...${RES}"
        mv /tmp/alist.bak "$INSTALL_PATH/alist"
        systemctl start alist
        exit 1
    }

    rm -f /tmp/alist.tar.gz /tmp/alist.bak
    systemctl restart alist
    echo -e "${GREEN_COLOR}更新完成！${RES}"
}

# 省略其余 UNINSTALL、INIT、RESET_PASSWORD、SUCCESS 等函数未变部分...
