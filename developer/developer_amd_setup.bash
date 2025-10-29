#!/bin/bash

# 错误处理函数
die() {
    echo "ERROR: $*" >&2
    exit 1
}
# ====================== 初始配置 ======================
echo "请注意！！！该安装程序为开发者使用，适配 amd 架构，安装采集平台所需的软件、服务"
read -p "按回车键继续..."
# 预定义的机器人类型列表（可根据实际情况扩展）
KNOWN_ROBOT_TYPES=("aloha" "pika" "realman" "dexterous_hand" "so101" "galaxea" "galbot")
 
while true; do
    read -p "请输入您的机器人类型（例如：aloha, pika, realman, dexterous_hand, so101, galaxea, galbot等）: " robot_type
    
    # 检查输入是否为空
    if [[ -z "$robot_type" ]]; then
        echo "错误：机器人类型不能为空，请重新输入！"
        continue
    fi
 
    # 检查是否是已知机器人类型
    is_known_type=false
    for type in "${KNOWN_ROBOT_TYPES[@]}"; do
        if [[ "$robot_type" == "$type" ]]; then
            is_known_type=true
            break
        fi
    done
 
    # 如果是新类型，给出提示
    if [[ $is_known_type == false ]]; then
        echo "警告：'${robot_type}' 不是预定义的机器人类型。"
        echo "请确保这是您想要的名称。"
        read -p "是否确认使用此名称？(y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "请重新输入机器人类型。"
            continue
        fi
    fi
 
    echo "您输入的机器人类型是: ${robot_type}"
    break
done
# 获取脚本所在目录（处理符号链接情况）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd "$SCRIPT_DIR" || die "无法进入脚本目录"

# 定义变量
BACKEND_REPO="https://github.com/BAAI-EI-DATA/WanX-Studio-Server.git"
DOCKER_IMAGES=("baai-flask-server-amd.tar")
NGINX_CONFS=("baai_server_ceshi.conf" "baai_server_release.conf")

# 检查必需文件是否存在
REQUIRED_FILES=("${NGINX_CONFS[@]}")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        die "错误：必需文件 $file 不存在，请确保它在脚本同级目录下"
    fi
done


# 检查是否为root用户
if [ "$(id -u)" -eq 0 ]; then
    die "请使用普通用户运行此脚本，避免权限问题"
fi

# ====================== 步骤1: 网络配置 ======================
echo "步骤1: 请手动配置网络（如使用 nmcli 或编辑 /etc/netplan/），确保优先使用 BAAI_GJ \ BAAI 网络"
read -p "按回车键继续..."

# ====================== 步骤2: 确认用户名 ======================
CURRENT_USER=$(whoami)
read -p "当前用户名为 '$CURRENT_USER'，是否确认？(y/n) " confirm
if [ "$confirm" != "y" ]; then
    read -p "请输入正确的用户名: " CURRENT_USER
fi
echo "记录用户名: $CURRENT_USER"

# ====================== 步骤3: 安装 Docker ======================
echo "步骤3: 检查并安装 Docker..."

# 检查是否已安装 Docker
if command -v docker &>/dev/null; then
    echo "Docker 已安装，版本信息如下："
    docker --version
    echo "将用户 $USER 加入 docker 组..."
    sudo usermod -aG docker "$USER"
    echo "跳过安装步骤，但会继续执行配置和验证..."
else
    # 安装依赖
    echo "安装必要依赖..."
    sudo apt-get update
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common

    # 添加 Docker 官方 GPG 密钥
    echo "添加 Docker 官方 GPG 密钥..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # 设置 Docker 稳定版仓库
    echo "配置 Docker 官方软件源..."
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 安装 Docker 引擎
    echo "安装 Docker 引擎..."
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # 启动 Docker 并设置开机自启（即使已安装也要确保服务运行）
    sudo systemctl enable docker
    sudo systemctl start docker

    # 将当前用户加入 docker 组（避免每次使用 sudo）
    echo "将用户 $USER 加入 docker 组..."
    sudo usermod -aG docker "$USER"
	echo "正在刷新组权限，部分系统需要重启终端，再次运行该脚本"
    newgrp docker || true  # 刷新组权限（部分系统可能需要重启终端）

    # 验证安装（即使已安装也要运行验证）
    echo "验证 Docker 安装..."
    if ! sudo docker run --rm hello-world &>/dev/null; then
        echo "错误：Docker 安装验证失败！请检查日志。"
        exit 1
    fi

    echo "Docker 配置完成！版本信息："
    docker --version
fi


# ====================== 步骤4: 安装 Git ======================
echo "步骤4: 检查并安装 Git..."
if ! command -v git &>/dev/null; then
    sudo apt install -y git || die "Git 安装失败"
    echo "Git 安装完成"
else
    echo "Git 已安装，跳过"
fi

# ====================== 步骤5: 安装并配置 Nginx ======================
echo "步骤5: 检查并安装 Nginx..."
if ! command -v nginx &>/dev/null; then
    sudo apt install -y nginx || die "Nginx 安装失败"
    echo "Nginx 安装完成"
else
    echo "Nginx 已安装，跳过"
fi

# 配置 Nginx
echo "配置 Nginx..."
for conf in "${NGINX_CONFS[@]}"; do
    sed "s|/home/agilex/|/home/$CURRENT_USER/|g" "$SCRIPT_DIR/$conf" | sudo tee "/etc/nginx/conf.d/$conf" >/dev/null
    echo "已配置 $conf 并替换用户名为 $CURRENT_USER"
done
# 1. 检查当前 nginx.service 文件内容
if ! grep -q "WantedBy=multi-user.target" "/usr/lib/systemd/system/nginx.service"; then
    sudo mkdir -p /etc/systemd/system/nginx.service.d
    echo "[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/nginx.service.d/override.conf >/dev/null
    sudo systemctl daemon-reload
fi

# 启动 Nginx
sudo systemctl start nginx
sudo systemctl enable nginx
sudo nginx -t || die "Nginx 配置测试失败，请检查 /etc/nginx/conf.d/ 下的配置文件"
sudo systemctl reload nginx || die "Nginx 重载失败"

# 配置 logtail
LOGTAIL_DIR="/usr/local/ilogtail"
APP_INFO_FILE="${LOGTAIL_DIR}/app_info.json"
 
# 检查 Logtail 是否已安装（通过 app_info.json 是否存在且包含版本信息）
if [ -f "$APP_INFO_FILE" ] && grep -q "loongcollector_version" "$APP_INFO_FILE"; then
    echo "Logtail 已安装，版本信息："
    sudo cat "$APP_INFO_FILE" | grep "loongcollector_version"
    # 其他后续操作...
else
    echo "Logtail 未安装，开始配置和安装..."
 
    # 配置目录权限
    sudo mkdir -p /opt/wanx_studio/
    sudo chown -R "$USER":"$USER" /opt/wanx_studio/
    sudo chmod -R 777 /opt/wanx_studio/
 
    # 创建 Logtail 用户标识文件
    sudo mkdir -p /etc/ilogtail/users
    sudo touch /etc/ilogtail/users/1560822971114422
    echo "robot-baai-any" | sudo tee /etc/ilogtail/user_defined_id > /dev/null
 
    # 下载并安装 Logtail
    LOGTAIL_SCRIPT="loongcollector.sh"
    if [ ! -f "$LOGTAIL_SCRIPT" ]; then
        echo "下载 Logtail 安装脚本..."
        wget http://aliyun-observability-release-cn-beijing.oss-cn-beijing.aliyuncs.com/loongcollector/linux64/latest/loongcollector.sh -O "$LOGTAIL_SCRIPT"
        chmod 755 "$LOGTAIL_SCRIPT"
    else
        echo "检测到已下载的安装脚本，跳过下载。"
    fi
 
    echo "安装 Logtail..."
    sudo ./"$LOGTAIL_SCRIPT" install cn-beijing-internet
 
    # 再次检查安装结果
    if [ -f "$APP_INFO_FILE" ] && grep -q "loongcollector_version" "$APP_INFO_FILE"; then
        echo "Logtail 安装成功！版本信息："
        sudo cat "$APP_INFO_FILE" | grep "loongcollector_version"
    else
        echo "错误：Logtail 安装失败，未找到版本信息文件！"
        exit 1
    fi
fi

# ====================== 步骤6: 部署代码 ======================
echo "步骤6: 部署代码..."

# 后端代码（检查目录是否存在）
BACKEND_DIR="/opt/WanX-Studio-Server"
if [ ! -d "$BACKEND_DIR" ]; then
    cd "/opt" || die "无法进入目录"
    sudo git clone "$BACKEND_REPO" || die "克隆后端仓库失败"
    sudo chown -R $USER:$USER /opt/WanX-Studio-Server
    sudo chmod -R 777 /opt/WanX-Studio-Server
    cd "WanX-Studio-Server" || die "无法进入后端目录"
    echo "后端代码克隆完成"
else
    sudo chown -R $USER:$USER /opt/WanX-Studio-Server
    sudo chmod -R 777 /opt/WanX-Studio-Server
    echo "后端目录 $BACKEND_DIR 已存在，跳过克隆"
fi

# ====================== 步骤7: 加载 Docker 镜像 ======================
echo "步骤7: 加载 Docker 镜像..."

for img in "${DOCKER_IMAGES[@]}"; do
    img_name=$(basename "$img" .tar)
    load_image="n"  # 默认跳过

    # 询问是否加载本地镜像
    while true; do
        read -p "是否加载本地镜像 ${img_name}？(y/n) " load_image
        case "$load_image" in
            y|Y) 
                # 检查文件是否存在
                if [[ ! -f "$SCRIPT_DIR/$img" ]]; then
                    echo "警告：镜像文件 $SCRIPT_DIR/$img 不存在，跳过"
                    continue 2
                fi
                # 加载本地镜像
                echo "正在加载本地镜像 $img_name ..."
                if sudo docker load -i "$SCRIPT_DIR/$img"; then
                    echo "成功加载镜像 $img_name"
                else
                    echo "错误：加载镜像 $img_name 失败"
                    exit 1
                fi
                break
                ;;
            n|N) 
                echo "跳过本地镜像 ${img_name}"
                # 修改：使用指定的 Docker Hub 拉取 + 重命名逻辑
                while true; do
                    read -p "是否从 Docker Hub 拉取镜像 ${img_name}？(y/n) " pull_image
                    case "$pull_image" in
                        y|Y)
                            echo "正在拉取镜像 liuyou1103/wanx-server:tag ..."
                            if sudo docker pull "liuyou1103/wanx-server:tag"; then
                                echo "成功拉取镜像 liuyou1103/wanx-server:tag"
                                # 重命名为本地需要的镜像名
                                echo "正在重命名为 ${img_name}:latest ..."
                                if sudo docker tag "liuyou1103/wanx-server:tag" "${img_name}:latest"; then
                                    echo "成功重命名为 ${img_name}:latest"
                                else
                                    echo "错误：重命名镜像失败"
                                    exit 1
                                fi
                            else
                                echo "错误：拉取镜像 liuyou1103/wanx-server:tag 失败"
                                exit 1
                            fi
                            break 2  # 跳出两层循环
                            ;;
                        n|N) 
                            echo "跳过镜像 ${img_name}（后续可能影响服务启动）"
                            continue 3  # 跳出两层循环，处理下一个镜像
                            ;;
                        *) 
                            echo "请输入 y 或 n" 
                            ;;
                    esac
                done
                break
                ;;
            *) 
                echo "请输入 y 或 n" 
                ;;
        esac
    done
done
# ====================== 步骤8: 配置免密 sudo ======================
echo "步骤8: 配置免密 sudo..."
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: /sbin/ip, /sbin/modprobe, /usr/sbin/ethtool" | sudo tee "/etc/sudoers.d/baai_nopasswd_$CURRENT_USER" >/dev/null

# ====================== 步骤9: 测试启动服务 ======================
echo "步骤9: 测试启动服务..."

# 启动后端服务
if [ -d "$BACKEND_DIR/arch64" ]; then
    cd "$BACKEND_DIR/arch64" || die "无法进入后端服务目录"
    echo "配置后台服务..."
    # 定义配置文件路径
    SETUP_FILE="$BACKEND_DIR/arch64/setup.yaml"
 
    # 检查配置文件是否存在
    if [ ! -f "$SETUP_FILE" ]; then
    echo "错误: setup.yaml 配置文件不存在于预期路径: $SETUP_FILE"
    exit 1
    fi
 
    echo "获取运行版本"
    while true; do
        read -p "请选择运行版本(dev/release): " device_server_type
        if [ "$device_server_type" = "dev" ] || [ "$device_server_type" = "release" ]; then
	    break
        else
	    echo "无效输入，请输入 dev 或 release"
        fi
    done
 
    echo "获取上传方式"
    while true; do
        read -p "请选择上传方式(nas/ks3): " upload_type
        if [ "$upload_type" = "nas" ] || [ "$upload_type" = "ks3" ]; then
	    break
        else
	    echo "无效输入，请输入 nas 或 ks3"
        fi
    done
 
    echo "正在更新配置文件..."
 
    # 直接更新配置文件（使用sed进行原地修改）
    sed -i "s/^robot_type:.*/robot_type: $robot_type/" "$SETUP_FILE"
    sed -i "s/^device_server_type:.*/device_server_type: $device_server_type/" "$SETUP_FILE"
    sed -i "s/^upload_type:.*/upload_type: $upload_type/" "$SETUP_FILE"
    bash start_server_docker.sh || die "启动后端服务失败"
else
    echo "警告: 后端服务目录不存在，跳过启动"
fi


# ====================== 步骤10: 开机后操作 ======================
echo "步骤10: 开机后操作..."
# 输出采集平台 URL
echo "采集平台测试访问地址: http://localhost:5605/hmi"
echo "采集平台正式访问地址: http://localhost:5805/hmi"
echo "访问平台网址即可"
echo "所有步骤完成！"
echo "请注意！！！请按版本自行安装机器控制程序后，再开始采集"
