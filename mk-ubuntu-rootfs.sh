#!/bin/bash -e

# Directory contains the target rootfs
TARGET_ROOTFS_DIR="binary"

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

echo -e "\033[36m Building for arm64 \033[0m"

if [ ! $VERSION ]; then
	VERSION="debug"
fi

./ch-mount.sh -u $TARGET_ROOTFS_DIR || true

BASE_IMAGE="ubuntu22.04.5-base-arm64-$GUI.tar.gz"
if [ ! -e "$BASE_IMAGE" ]; then
    echo -e "\033[31m 错误: 请先运行mk-base-ubuntu.sh生成$BASE_IMAGE \033[0m"
    exit 1
fi

LINUX_UPDATE_DEB_HEADERS="../linux-headers-5.10.209_5.10.209-*_arm64.deb"
LINUX_UPDATE_DEB_IMAGE="../linux-image-5.10.209_5.10.209-*_arm64.deb"
LINUX_UPDATE_DEB_LIBC_DEV="../linux-libc-dev_5.10.209-*_arm64.deb"

# 检查三个DEB包是否存在
if [ ! -e $LINUX_UPDATE_DEB_HEADERS ] || [ ! -e $LINUX_UPDATE_DEB_IMAGE ] || [ ! -e $LINUX_UPDATE_DEB_LIBC_DEV ]; then
    echo -e "\033[31m错误: 缺少必要的DEB包,请确认以下文件存在: \n$LINUX_UPDATE_DEB_HEADERS\n$LINUX_UPDATE_DEB_IMAGE\n$LINUX_UPDATE_DEB_LIBC_DEV\033[0m"
    exit 1
fi

echo -e "\033[36m Extract image \033[0m"

if [ -d $TARGET_ROOTFS_DIR ] ; then
    echo "\033[36m rm old $TARGET_ROOTFS_DIR/ \033[0m"
    ./ch-mount.sh -u $TARGET_ROOTFS_DIR || true
    sudo rm -rf $TARGET_ROOTFS_DIR/ || true
    sudo tar -xpf ubuntu22.04.5-base-arm64-$GUI.tar.gz
fi

# packages folder
sudo mkdir -p $TARGET_ROOTFS_DIR/packages
sudo cp -rpf packages/arm64/* $TARGET_ROOTFS_DIR/packages
sudo mkdir -p $TARGET_ROOTFS_DIR/packages/linux-deb
sudo cp ../linux-headers-5.10.209_5.10.209-*_arm64.deb $TARGET_ROOTFS_DIR/packages/linux-deb
sudo cp ../linux-image-5.10.209_5.10.209-*_arm64.deb $TARGET_ROOTFS_DIR/packages/linux-deb
sudo cp ../linux-libc-dev_5.10.209-*_arm64.deb $TARGET_ROOTFS_DIR/packages/linux-deb

# overlay folder
sudo cp -rpf overlay/* $TARGET_ROOTFS_DIR/

# overlay-firmware folder
sudo cp -rpf overlay-firmware/* $TARGET_ROOTFS_DIR/

# overlay-debug folder
# adb, video, camera  test file
if [ "$VERSION" == "debug" ]; then
	sudo cp -rf overlay-debug/* $TARGET_ROOTFS_DIR/
fi
## hack the serial
sudo mkdir -p $TARGET_ROOTFS_DIR/lib/systemd/system/
sudo cp -f overlay/usr/lib/systemd/system/serial-getty@.service $TARGET_ROOTFS_DIR/lib/systemd/system/

# adb
if [[ "$VERSION" == "debug" ]]; then
	sudo cp -f overlay-debug/usr/local/share/adb/adbd-64 $TARGET_ROOTFS_DIR/usr/bin/adbd
fi

echo -e "\033[36m wifi bt install....................\033[0m"
# bt/wifi firmware
WIFI_BT_BASE_PATCH="../external/rkwifibt"
WIFI_BT_FIRMWARE_PATCH="$WIFI_BT_BASE_PATCH/firmware"
WIFI_BT_SCRIPTS_PATCH="$WIFI_BT_BASE_PATCH/scripts"
WIFI_BT_TOOL_PATCH="$WIFI_BT_BASE_PATCH/tools"

sudo mkdir -p $TARGET_ROOTFS_DIR/system/lib/modules/
sudo mkdir -p $TARGET_ROOTFS_DIR/system/etc/firmware/
sudo mkdir -p $TARGET_ROOTFS_DIR/vendor/etc
sudo cp -avf $WIFI_BT_SCRIPTS_PATCH/* $TARGET_ROOTFS_DIR/usr/bin/
sudo cp -avf $WIFI_BT_BASE_PATCH/wifibt-init.service $TARGET_ROOTFS_DIR/lib/systemd/system/
sudo mkdir -p $TARGET_ROOTFS_DIR/etc/systemd/system/wifibt-init.service.d
sudo tee "$TARGET_ROOTFS_DIR/etc/systemd/system/wifibt-init.service.d/add-delay.conf" >/dev/null <<EOI
[Service]
ExecStartPre=/bin/sleep 5
EOI

# sudo find $WIFI_BT_FIRMWARE_PATCH/ -type f -exec cp {} "$TARGET_ROOTFS_DIR/system/etc/firmware/" \;
# sudo find $WIFI_BT_TOOL_PATCH/ -type f -executable -exec cp -avf {} $TARGET_ROOTFS_DIR/usr/bin/ \;

echo -e "\033[36m Change root.....................\033[0m"

sudo cp /usr/bin/qemu-aarch64-static $TARGET_ROOTFS_DIR/usr/bin/

sudo cp -f /etc/resolv.conf $TARGET_ROOTFS_DIR/etc/

./ch-mount.sh -m $TARGET_ROOTFS_DIR

cat << EOF | sudo chroot $TARGET_ROOTFS_DIR

# Set environment variables
export LC_ALL=C.UTF-8
export DEBIAN_FRONTEND=noninteractive
export APT_INSTALL="apt-get install -fy --allow-downgrades"

# System update and upgrade
apt-get update
apt-get full-upgrade -y

\${APT_INSTALL} aptitude

# Fix permissions
chmod o+x /usr/lib/dbus-1.0/dbus-daemon-launch-helper

#---------------------------
# Desktop specific configuration
#---------------------------
if [ "$GUI" == "desktop" ]; then
    # Set wallpaper
    echo -e "\033[36m Setting wallpaper... \033[0m"
    ln -sf /usr/share/backgrounds/tspi_wallpaper.png /usr/share/xfce4/backdrops/xubuntu-wallpaper.png
    
    # Remove unnecessary bluetooth stack
    echo -e "\033[36m Removing desktop bluetooth components... \033[0m"
    apt-get purge -y gnome-bluetooth
fi

#---------------------------
# Common package installation
#---------------------------
echo -e "\033[36m Installing core system packages... \033[0m"
\${APT_INSTALL} bluez bluez-tools

#---------------------------
# Power management setup
#---------------------------
echo -e "\033[36m Configuring power management... \033[0m"
\${APT_INSTALL} pm-utils triggerhappy bsdmainutils
cp /etc/Powermanager/triggerhappy.service /lib/systemd/system/triggerhappy.service
sed -i "s/#HandlePowerKey=.*/HandlePowerKey=ignore/" /etc/systemd/logind.conf
systemctl enable triggerhappy.service

#---------------------------
# Hardware acceleration setup
#---------------------------
echo -e "\033[36m Installing RGA components... \033[0m"
\${APT_INSTALL} /packages/rga/*.deb

#---------------------------
# Multimedia stack installation
#---------------------------
if [ "$GUI" == "desktop" ]; then
    echo -e "\033[36m Installing desktop multimedia stack... \033[0m"
    \${APT_INSTALL} gstreamer1.0-plugins-bad gstreamer1.0-plugins-base \
    gstreamer1.0-tools gstreamer1.0-alsa qtmultimedia5-examples
else
    echo -e "\033[36m Installing minimal multimedia components... \033[0m"
fi
\${APT_INSTALL} /packages/mpp/* /packages/gst-rkmpp/*.deb

#---------------------------
# Camera support
#---------------------------
echo -e "\033[36m Installing camera stack... \033[0m"
\${APT_INSTALL} cheese v4l-utils
cp -rf /packages/rkisp/*.deb /
cp -rf /packages/rkaiq/*.deb /
\${APT_INSTALL} /packages/libv4l/*.deb
aptitude install -y libv4l2rds0 libv4l-dev libv4l-0 libv4lconvert0

#---------------------------
# Graphics subsystem
#---------------------------
if [ "$GUI" == "desktop" ]; then
    echo -e "\033[36m Configuring X server... \033[0m"
    \${APT_INSTALL} /packages/xserver/*.deb
    apt-mark hold xserver-common xserver-xorg-core xserver-xorg-legacy
fi

#---------------------------
# Browser installation
#---------------------------
if [ "$GUI" == "desktop" ]; then
    echo -e "\033[36m Installing Chromium... \033[0m"
    \${APT_INSTALL} /packages/chromium/*.deb
fi

#---------------------------
# DRM stack configuration
#---------------------------
echo -e "\033[36m Configuring DRM components... \033[0m"
\${APT_INSTALL} /packages/libdrm/*.deb

if [ "$GUI" == "desktop" ]; then
    \${APT_INSTALL} /packages/libdrm-cursor/*.deb
    # Configure X server preload
    sed -i '/libdrm-cursor.so/d' /etc/ld.so.preload
    echo 'export LD_PRELOAD=libdrm-cursor.so.1' >> /usr/bin/X
fi

#---------------------------
# Linux update deb packages
#---------------------------
echo -e "\033[36m Installing Linux update deb packages... \033[0m"
dpkg -i /packages/linux-deb/*.deb

#---------------------------
# Wireless/BT configuration
#---------------------------
echo -e "\033[36m Installing wireless components... \033[0m"
\${APT_INSTALL} /packages/rkwifibt/*.deb
ln -sf /system/etc/firmware /vendor/etc/
ln -sf /system/etc/firmware/* /usr/lib/firmware/
echo "bcmdhd" | tee /etc/modules-load.d/bcmdhd.conf
chmod 644 /etc/systemd/system/wifibt-init.service.d/add-delay.conf
systemctl enable wifibt-init.service

#---------------------------
# glmark2
#---------------------------
echo -e "\033[36m Install glmark2.................... \033[0m"
\${APT_INSTALL} /packages/glmark2/*.deb

#---------------------------
# RKNPU2 for /etc/init.d/rockchip.sh
#---------------------------
echo -e "\033[36m Move the NPU compressed package to the root directory... \033[0m"
cp /packages/rknpu2/rknpu2.tar  /

#---------------------------
# GPU for /etc/init.d/rockchip.sh
#---------------------------
echo -e "\033[36m Move the GPU compressed package to the root directory... \033[0m"
cp /packages/libmali/libmali-*-x11*.deb /

#---------------------------
# System tools installation
#---------------------------
echo -e "\033[36m Installing system utilities... \033[0m"
\${APT_INSTALL} /packages/rktoolkit/*.deb

#---------------------------
# Desktop media components
#---------------------------
if [ "$GUI" == "desktop" ]; then
    echo -e "\033[36m Installing media playback components... \033[0m"
    \${APT_INSTALL} ffmpeg mpv /packages/ffmpeg/*.deb /packages/mpv/*.deb
    apt --fix-broken install -y
fi

#---------------------------
# TAB command completion
#---------------------------
apt update
\${APT_INSTALL} bash-completion

#---------------------------
# System cleanup
#---------------------------
echo -e "\033[36m Performing system cleanup... \033[0m"
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*

#---------------------------
# Systemd service configuration
#---------------------------
echo -e "\033[36m Configuring system services... \033[0m"
systemctl mask systemd-networkd-wait-online.service
systemctl mask NetworkManager-wait-online.service
rm -f /lib/systemd/system/wpa_supplicant@.service

#---------------------------
# Set Audio-Devices Description
#---------------------------
chown lckfb:lckfb /etc/udev/rules.d/95-audio-set-description.rules

#---------------------------
# RNIDS+ADB Plus run permission
#---------------------------
# auto dhcp usb0
tee -a /etc/network/interfaces <<EOI
auto usb0
iface usb0 inet dhcp
EOI

#---------------------------
# iptables switch to the legacy version for docker run
#---------------------------
echo -e "\033[36m Installing system utilities... \033[0m"
dpkg -i /packages/docker/lib*.deb
dpkg -i /packages/docker/ebtables*.deb
dpkg -i /packages/docker/iptables*.deb
apt --fix-broken install -y
update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-legacy 1
update-alternatives --set iptables /usr/sbin/iptables-legacy

#---------------------------
# Docker installation
#---------------------------
echo -e "\033[36m Install docker dependencies... \033[0m"
apt update
\${APT_INSTALL} apt-transport-https ca-certificates curl gnupg lsb-release libseccomp2
\${APT_INSTALL} uidmap
apt --fix-broken install -y
echo -e "\033[36m Docker installation... \033[0m"
dpkg -i /packages/docker/containerd.io_*.deb
dpkg -i /packages/docker/docker-ce-cli_*.deb
dpkg -i /packages/docker/docker-ce_*.deb
dpkg -i /packages/docker/docker-compose-plugin_*.deb
dpkg -i /packages/docker/docker-buildx-plugin_*.deb
apt --fix-broken install -y
systemctl enable docker.service

#---------------------------
# user groupadd
#---------------------------
usermod -aG docker lckfb
usermod -aG adm lckfb
usermod -aG sudo lckfb
usermod -aG video lckfb
usermod -aG audio lckfb
usermod -aG bluetooth lckfb

#---------------------------
# Add automatic login and disable the lock screen/sleep function
#---------------------------
if [ "$GUI" == "desktop" ]; then
    \${APT_INSTALL} ttf-wqy-zenhei xfonts-intl-chinese
    \${APT_INSTALL} guvcview
    \${APT_INSTALL} mpv acpid gnome-sound-recorder

    echo -e "\033[36m Configure automatic login and power management... \033[0m"
    # Install the necessary tools
    \${APT_INSTALL} xfce4-power-manager xfce4-screensaver x11-xserver-utils

    # Configure LightDM for automatic login
    mkdir -p /etc/lightdm/lightdm.conf.d
    echo "[Seat:*]
autologin-user=lckfb
autologin-user-timeout=0" > /etc/lightdm/lightdm.conf.d/10-autologin.conf

    # Set lightdm as the default display manager
    echo "/usr/sbin/lightdm" > /etc/X11/default-display-manager

    # Configure XFCE power management (system-level settings)
    mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/
    cat > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml <<EOFXFCE
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="dpms-enabled" type="bool" value="false"/>
    <property name="blank-on-ac" type="int" value="0"/>
    <property name="lock-screen-suspend-hibernate" type="bool" value="false"/>
    <property name="presentation-mode" type="bool" value="true"/>
  </property>
</channel>
EOFXFCE

    # Disable the screen saver program (system-level setting)
    cat > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml <<EOFXFCE
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-screensaver" version="1.0">
  <property name="saver" type="empty">
    <property name="saver-enabled" type="bool" value="false"/>
  </property>
</channel>
EOFXFCE

    # Disable DPMS and screen saver globally
    echo "xset s off -dpms" >> /etc/xdg/xfce4/xinitrc
    echo "xset s noblank" >> /etc/xdg/xfce4/xinitrc

    # Disable the system sleep function
    systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

    # Ensure the user directory permissions
    chown -R lckfb:lckfb /home/lckfb/.config
fi

#---------------------------
# clean
#---------------------------
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/
rm -rf /packages/

EOF

./ch-mount.sh -u $TARGET_ROOTFS_DIR || true

echo -e "\033[32m Root filesystem preparation completed successfully \033[0m"
