#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 恢复默认颜色

# 日志函数
log_info() { echo -e "${GREEN}[INFO] $* ${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $* ${NC}"; }
log_error() { echo -e "${RED}[ERROR] $* ${NC}"; }

# 初始化检测结果变量
ALL_CHECKS_PASS=true

# 检查是否通过sudo运行
check_sudo_privilege() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "\033[31m[错误] 必须使用 sudo 运行此脚本！\033[0m"
        echo -e "请执行：\n  sudo $0 $@"
        exit 1
    fi
}

# 系统版本检查函数: 推荐是Ubuntu 22.04 LTS (Jammy Jellyfish)
check_ubuntu_version() {
    local required_version="22.04"
    local required_codename="jammy"
    local is_supported=0

    # 通过LSB信息检查版本
    if command -v lsb_release &> /dev/null; then
        local os_id=$(lsb_release -si)
        local os_release=$(lsb_release -sr)
        local os_codename=$(lsb_release -sc)
        
        if [[ "$os_id" == "Ubuntu" && "$os_release" == "$required_version" && "$os_codename" == "$required_codename" ]]; then
            is_supported=1
        fi
    # 备用方案：通过os-release文件检查
    elif [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" == "ubuntu" && "$VERSION_ID" == "$required_version" && "$UBUNTU_CODENAME" == "$required_codename" ]]; then
            is_supported=1
        fi
    fi

    if [[ $is_supported -eq 1 ]]; then
        log_info "系统版本检测通过 (Ubuntu ${required_version} LTS)"
    else
        log_warn "不兼容的系统版本! 推荐使用Ubuntu ${required_version} LTS (Jammy Jellyfish)"
        log_warn "(继续使用当前系统编译可能会出现未知错误)"
        log_warn "当前系统信息: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME)"
    fi
}

# 检查CPU架构支持
check_cpu() {
    local arch_support=0
    grep -q -E 'vmx|svm' /proc/cpuinfo && arch_support=1
    
    if [[ $(uname -m) != "x86_64" ]]; then
        log_error "仅支持x86_64架构宿主机"
        ALL_CHECKS_PASS=false
    elif [[ $arch_support -eq 0 ]]; then
        log_warn "CPU虚拟化未启用(可能影响虚拟化应用运行)"
    else
        log_info "CPU架构支持检测通过"
    fi
}

# 检查内核模块支持
check_kernel() {
    declare -a required_modules=("overlay" "veth" "bridge" "zfs")
    
    for module in "${required_modules[@]}"; do
        if ! lsmod | grep -q $module; then
            log_error "内核模块 $module 未加载! ( 尝试 sudo modprobe $module)"
            log_error "如果您是在类似于Docker容器内运行, 请忽略此提示 !!"
            ALL_CHECKS_PASS=false
        fi
    done
}

# 网络检查
check_network() {
    local is_mirror_supported=0
    local is_base_pkg_supported=0

    log_info "正在检查网络连接..."
    
    # 测试软件源连接
    local MIRROR_URL="http://mirrors.cernet.edu.cn/ubuntu-ports/"
    if curl --output /dev/null --silent --head --fail --connect-timeout 30 "$MIRROR_URL"; then
        is_mirror_supported=1
        log_info "软件源连接正常"
    else
        ALL_CHECKS_PASS=false
        log_error "错误: 无法连接软件源 $MIRROR_URL"
        log_error "请检查以下可能原因: "
        log_error "1. 网络代理设置是否正确"
        log_error "2. 防火墙是否阻止访问教育网镜像"
        log_error "3. 镜像源是否暂时不可用"
        log_error "建议尝试: ping mirrors.cernet.edu.cn"
    fi

    # 测试基础包下载源
    local BASE_PKG_URL="http://cdimage.ubuntu.com/ubuntu-base/releases/22.04.5/release/ubuntu-base-22.04.5-base-arm64.tar.gz"
    if curl --output /dev/null --silent --head --fail --connect-timeout 30 "$BASE_PKG_URL"; then
        is_base_pkg_supported=1
        log_info "基础包下载源连接正常"
    else
        ALL_CHECKS_PASS=false
        log_error "错误: 无法访问基础包下载源 $BASE_PKG_URL"
        log_error "请检查以下可能原因: "
        log_error "1. 国际网络连接是否正常"
        log_error "2. Ubuntu CDN 是否暂时不可用"
        log_error "建议尝试: curl -I $BASE_PKG_URL"
    fi

    if [[ $is_mirror_supported -eq 1 && $is_base_pkg_supported -eq 1 ]]; then
        log_info "网络检查通过, 所有资源可用 !!"
    fi
}

# 存储空间检查(调整为系统根目录)
check_storage() {
    local min_disk=50 # 最小磁盘空间(GB)
    local available=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')

    if [[ $available -lt $min_disk ]]; then
        log_error "系统磁盘空间不足! ( 需要${min_disk}G, 当前可用: ${available}G)"
        ALL_CHECKS_PASS=false
    else
        log_info "存储空间检测通过(可用空间: ${available}G)"
    fi
}

# 软件依赖检查(新增核心开发工具检测)
check_dependencies() {
    declare -A required_packages=(
        # 基础编译工具
        ["build-essential"]="基本构建工具"
        ["crossbuild-essential-arm64"]="ARM64交叉编译基础包"
        ["gcc-9"]="GCC 9编译器"
        
        # 交叉编译工具链
        ["gcc-aarch64-linux-gnu"]="ARM64 GCC交叉编译器"
        ["g++-aarch64-linux-gnu"]="ARM64 G++交叉编译器"
        ["libc6-dev-arm64-cross"]="ARM64 C库开发文件"
        ["libgcc-11-dev-arm64-cross"]="ARM64 GCC运行时库"

        # 构建依赖库
        ["libssl-dev"]="SSL开发库"
        ["libelf-dev"]="ELF文件操作库"
        ["libgmp-dev"]="GMP数学库"
        ["libmpc-dev"]="MPC数学库"
        ["libncurses-dev"]="字符终端处理库"
        ["zfsutils-linux"]="ZFS文件系统工具"

        # 工具链组件
        ["binutils"]="二进制工具集合"
        ["ccache"]="编译缓存加速"
        ["cmake"]="跨平台构建工具"
        ["cpio"]="归档工具"
        ["device-tree-compiler"]="设备树编译工具"
        ["dkms"]="动态内核模块支持"
        ["dpkg-dev"]="Debian包开发工具"
        ["fakeroot"]="虚拟root环境"
        ["flex"]="词法分析器"
        ["bison"]="语法分析器"
        ["patchelf"]="ELF二进制修改工具"
        ["qemu-user-static"]="静态QEMU仿真器"

        # 系统工具
        ["apparmor"]="安全模块"
        ["binfmt-support"]="二进制格式支持"
        ["ca-certificates"]="CA证书"
        ["locales"]="本地化配置"
        ["lsb-release"]="LSB版本信息"
        ["util-linux"]="系统工具集"
        ["u-boot-tools"]="U-Boot工具"

        # 开发辅助
        ["git"]="版本控制系统"
        ["whiptail"]="对话框工具"
        ["rsync"]="高效文件同步"
        ["unzip"]="解压工具"
        ["vim"]="文本编辑器"
        ["net-tools"]="网络工具包"
        ["python3"]="Python3解释器"
        ["python3-pip"]="Python包管理"
        ["curl"]="网络传输工具"
        ["iputils-ping"]="网络测试工具"
    )

    log_info "检查系统依赖包..."
    for pkg in "${!required_packages[@]}"; do
        if ! dpkg-query -W --showformat='${Status}\n' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            log_error "缺失依赖包: ${required_packages[$pkg]} ($pkg)\n  修复命令: sudo apt-get install $pkg"
            log_info "正在自动修复..."
            if ! sudo apt-get install -y $pkg; then
                log_error "自动修复失败, 请手动安装缺失的依赖包"
                ALL_CHECKS_PASS=false
                echo " "
            else
                log_info "依赖包 ${required_packages[$pkg]} ($pkg) 安装成功"
                echo " "
            fi
        fi
    done
}

# 检查QEMU支持(新增静态二进制验证)
check_qemu() {
    if ! which qemu-aarch64-static &> /dev/null; then
        log_error "QEMU静态二进制未安装! ( 执行: sudo apt-get install qemu-user-static)"
        ALL_CHECKS_PASS=false
    elif [[ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
        log_error "aarch64架构支持未启用! ( 执行: sudo update-binfmts --enable qemu-aarch64)"
        log_info "正在自动启用..."
        if ! sudo update-binfmts --enable qemu-aarch64; then
            log_error "自动启用失败, 请手动启用"
            ALL_CHECKS_PASS=false
        else
            log_info "QEMU aarch64支持已启用"
        fi
    else
        log_info "QEMU跨架构支持检测通过"
    fi
}

# 执行检测流程
check_sudo_privilege "$@"
log_info "开始宿主机环境检测..."
check_cpu
check_ubuntu_version
check_kernel
check_dependencies
check_network
check_storage
check_qemu

echo "===================================="

# 最终结果汇总
if $ALL_CHECKS_PASS; then
    log_info "✅ 所有检测通过, 环境准备就绪"
else
    log_error "❌ 存在未通过的检测项, 请根据提示修复!!"
    exit 1
fi