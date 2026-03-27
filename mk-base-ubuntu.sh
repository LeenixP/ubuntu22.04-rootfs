#!/bin/bash -e

if [ -z "$GUI" ]; then
    echo -e "\033[36m *********************************************\033[0m"
    echo -e "\033[36m            是否需要带界面版本\033[0m"                    
    echo -e "\033[36m     选择desktop会安装xubuntu-core桌面\033[0m"
    echo -e "\033[36m       选择console为无桌面服务器版本\033[0m"
    echo -e "\033[36m *********************************************\033[0m"

    while true; do
        read -p "请输入您的选择(desktop或console): " GUI  
        # 检查输入是否为yes或no
        if [ "$GUI" == "desktop" ]; then
            GUI='desktop'
            break
        elif [ "$GUI" == "console" ]; then
            GUI='console'
            break
        else
            echo -e "\033[36m 格式错误请重新输入\033[0m"
        fi
    done
fi

# 最终输出结果
if [ "$GUI" == "desktop" ]; then
  echo "您选择了带界面版本。"
elif [ "$GUI" == "console" ]; then
  echo "您选择了不带界面版本。"
fi

TARGET_ROOTFS_DIR="binary"

apt_user_install=(
    "net-tools"               # 网络工具包，包含ifconfig、arp、netstat等
    "openssh-server"          # OpenSSH服务器
    "ifupdown"                # 网络接口配置工具
    "alsa-utils"              # ALSA声音驱动的用户空间工具
    "ntp"                     # 网络时间协议
    "network-manager"         # 网络管理器
    "gdb"                     # GNU调试器
    "inetutils-ping"          # ping命令，网络测试工具
    "libssl-dev"              # OpenSSL开发库
    "vsftpd"                  # FTP服务器
    "tcpdump"                 # 网络数据包分析工具
    "can-utils"               # CAN总线工具
    "i2c-tools"               # I2C工具
    "strace"                  # 系统调用跟踪工具
    "vim"                     # 文本编辑器
    "iperf3"                  # 网络性能测试工具
    "ethtool"                 # 网络接口配置工具
    "netplan.io"              # 网络配置工具
    "toilet"                  # 命令行文字艺术工具
    "htop"                    # 交互式进程查看器
    "pciutils"                # PCI设备工具
    "usbutils"                # USB设备工具
    "curl"                    # 命令行文件传输工具
    "whiptail"                # 命令行对话框工具
    "gnupg"                   # GnuPG加密工具
    "bc"                      # 命令行计算器
    "xinput"                  # 输入设备配置工具
    "gdisk"                   # GPT分区工具
    "parted"                  # 磁盘分区工具
    "gcc"                     # GNU编译器
    "sox"                     # 命令行音频处理工具
    "libsox-fmt-all"          # SoX的所有音频格式支持
    "gpiod"                   # GPIO工具
    "libgpiod-dev"            # GPIO开发库
    "python3-pip"             # Python3的包管理工具
    "python3-libgpiod"        # Python3的GPIO库
)
py_user_install=(
    ""               # 
)

if [ -e ubuntu22.04.5-base-arm64-$GUI.tar.gz ]; then
    sudo rm ubuntu22.04.5-base-arm64-$GUI.tar.gz
fi

if [ -d "$TARGET_ROOTFS_DIR" ]; then
    echo -e "\033[36mRemoving old $TARGET_ROOTFS_DIR/ \033[0m"
    if mountpoint -q "$TARGET_ROOTFS_DIR/dev"; then
        echo "$TARGET_ROOTFS_DIR/dev is mounted, unmounting..."
        sudo umount "$TARGET_ROOTFS_DIR/dev"
    fi
    if mountpoint -q "$TARGET_ROOTFS_DIR/proc"; then
        echo "$TARGET_ROOTFS_DIR/proc is mounted, unmounting..."
        sudo umount "$TARGET_ROOTFS_DIR/proc"
    fi
    if mountpoint -q "$TARGET_ROOTFS_DIR/sys"; then
        echo "$TARGET_ROOTFS_DIR/sys is mounted, unmounting..."
        sudo umount "$TARGET_ROOTFS_DIR/sys"
    fi
    echo "Removing directory $TARGET_ROOTFS_DIR/"
    sudo rm -rf "$TARGET_ROOTFS_DIR/"
else
    echo "$TARGET_ROOTFS_DIR does not exist."
fi

if [ ! -d $TARGET_ROOTFS_DIR ] ; then
    sudo mkdir -p $TARGET_ROOTFS_DIR

    if [ ! -e ubuntu-base-22.04.5-base-arm64.tar.gz ]; then
        echo "\033[36m wget ubuntu-base-20.04-base-arm64.tar.gz \033[0m"
        wget -c http://cdimage.ubuntu.com/ubuntu-base/releases/22.04.5/release/ubuntu-base-22.04.5-base-arm64.tar.gz
    fi
    sudo tar -xzvf ubuntu-base-22.04.5-base-arm64.tar.gz -C $TARGET_ROOTFS_DIR/
    sudo cp -b /etc/resolv.conf $TARGET_ROOTFS_DIR/etc/resolv.conf
    sudo cp -b sources.list $TARGET_ROOTFS_DIR/etc/apt/
    sudo cp -b /usr/bin/qemu-aarch64-static $TARGET_ROOTFS_DIR/usr/bin/
    sudo update-binfmts --enable qemu-aarch64
fi

finish() {
    ./ch-mount.sh -u $TARGET_ROOTFS_DIR
    echo -e "error exit"
    exit -1
}
trap finish ERR

echo "\033[36m Change root.....................\033[0m"

sudo ./ch-mount.sh -m $TARGET_ROOTFS_DIR

cat <<EOF | sudo chroot $TARGET_ROOTFS_DIR/
export DEBIAN_FRONTEND=noninteractive
export APT_INSTALL="apt-get install -fy --allow-downgrades"
export LC_ALL=C.UTF-8
apt-get -y update
apt-get -f -y upgrade

if [ "$GUI" == "desktop" ]; then
    apt install -y xubuntu-core onboard rsyslog sudo dialog apt-utils ntp evtest udev
    mv /var/lib/dpkg/info/ /var/lib/dpkg/info_old/
    mkdir /var/lib/dpkg/info/
    apt-get update
    apt install -y xubuntu-core onboard rsyslog sudo dialog apt-utils ntp evtest udev
    mv /var/lib/dpkg/info_old/* /var/lib/dpkg/info/
else
    apt install -y rsyslog sudo dialog apt-utils ntp evtest acpid
fi

#------------------user install------------
\${APT_INSTALL} ${apt_user_install[@]}
apt-get install -fy 
\${APT_INSTALL} ${apt_user_install[@]}
apt-get install -fy 

if [ "$GUI" == "desktop" ]; then
    \${APT_INSTALL} ttf-wqy-zenhei xfonts-intl-chinese
    \${APT_INSTALL} guvcview
    \${APT_INSTALL} mpv acpid gnome-sound-recorder
fi

echo exit 101 > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
apt install -y blueman
rm -f /usr/sbin/policy-rc.d

HOST=lckfb

# Create User
useradd -G sudo -m -s /bin/bash lckfb
passwd lckfb <<IEOF
lckfb
lckfb
IEOF
gpasswd -a lckfb video
gpasswd -a lckfb audio
passwd root <<IEOF
root
root
IEOF

# 设置主机名
echo lckfb > /etc/hostname

# Enable lightdm autologin for lckfb user
if [ -e /etc/gdm3/custom.conf ]; then
  sed -i "s|^#AutomaticLogin=.*|AutomaticLogin=lckfb|" /etc/gdm3/custom.conf
  sed -i "s|^#AutomaticLoginEnable=.*|AutomaticLoginEnable=true|" /etc/gdm3/custom.conf
fi

ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# workaround 90s delay
services=(NetworkManager systemd-networkd)
for service in ${services[@]}; do
  systemctl mask ${service}-wait-online.service
done

# disable the wire/nl80211
systemctl mask wpa_supplicant-wired@
systemctl mask wpa_supplicant-nl80211@
systemctl mask wpa_supplicant@

# Make systemd less spammy
sed -i 's/#LogLevel=info/LogLevel=warning/' /etc/systemd/system.conf
sed -i 's/#LogTarget=journal-or-kmsg/LogTarget=journal/' /etc/systemd/system.conf

# check to make sure sudoers file has ref for the sudo group
SUDOEXISTS="$(awk '$1 == "%sudo" { print $1 }' /etc/sudoers)"
if [ -z "$SUDOEXISTS" ]; then
  # append sudo entry to sudoers
  echo "# Members of the sudo group may gain root privileges" >> /etc/sudoers
  echo "%sudo ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi

# make sure that NOPASSWD is set for %sudo
sed -i -e '
/\%sudo/ c \
%sudo ALL=(ALL) NOPASSWD: ALL
' /etc/sudoers

sync

EOF

./ch-mount.sh -u $TARGET_ROOTFS_DIR

sudo tar zcvf ubuntu22.04.5-base-arm64-$GUI.tar.gz $TARGET_ROOTFS_DIR

echo -e "normal exit"
