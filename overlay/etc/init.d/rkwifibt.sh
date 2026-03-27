#!/bin/bash -e
### BEGIN INIT INFO
# Provides:          rockchip
# Required-Start:
# Required-Stop:
# Default-Start:
# Default-Stop:
# Short-Description:
# Description:       Setup rockchip platform environment
### END INIT INFO

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

init_rkwifibt() {
    case $1 in
        rk3288)
	    rk_wifi_init /dev/ttyS0
            ;;
        rk3399|rk3399pro)
	    rk_wifi_init /dev/ttyS0
            ;;
        rk3328)
	    rk_wifi_init /dev/ttyS0
            ;;
        rk3326|px30)
	    rk_wifi_init /dev/ttyS1
            ;;
        rk3128|rk3036)
	    rk_wifi_init /dev/ttyS0
            ;;
        rk3566)
	    rk_wifi_init /dev/ttyS1
            ;;
        rk3568)
	    rk_wifi_init /dev/ttyS8
            ;;
        rk3588|rk3588s)
	    rk_wifi_init /dev/ttyS8
            ;;
    esac
}

kernel_version=$(uname -r)
create_mod_symlink() {
    local source_file="$1"
    local link_name="$2"

    if [ -L "$link_name" ]; then
        echo "Symbolic link already exists: $link_name"
        return 0
    fi

    if [ ! -e "$source_file" ]; then
        echo "Source file does not exist: $source_file"
        return 1
    fi

    local link_dir
    link_dir=$(dirname "$link_name")
    if [ ! -d "$link_dir" ]; then
        echo "Target directory does not exist: $link_dir"
        return 1
    fi

    ln -s "$source_file" "$link_name"
    echo "Symbolic link created: $link_name -> $source_file"
}

kernel_version=$(uname -r)

declare -A symlinks=(
    ["/usr/lib/modules/$kernel_version/kernel/drivers/net/wireless/rockchip_wlan/rkwifi/bcmdhd/bcmdhd.ko"]="/system/lib/modules/bcmdhd.ko"
    ["/usr/lib/modules/$kernel_version/kernel/drivers/net/wireless/realtek/rtlwifi/rtl8192ee/rtl8192ee.ko"]="/system/lib/modules/8192ee.ko"
    ["/usr/lib/modules/$kernel_version/kernel/drivers/net/wireless/realtek/rtlwifi/rtl8192cu/rtl8192cu.ko"]="/system/lib/modules/8192cu.ko"
    ["/usr/lib/modules/$kernel_version/kernel/drivers/net/wireless/realtek/rtlwifi/rtl8723be/rtl8723be.ko"]="/system/lib/modules/8723be.ko"
    ["/usr/lib/modules/$kernel_version/kernel/drivers/net/wireless/realtek/rtlwifi/rtl8188ee/rtl8188ee.ko"]="/system/lib/modules/8188ee.ko"
    ["/usr/lib/modules/$kernel_version/kernel/drivers/net/wireless/realtek/rtlwifi/rtl8723ae/rtl8723ae.ko"]="/system/lib/modules/8723ae.ko"
    ["/usr/lib/modules/$kernel_version/kernel/drivers/net/wireless/realtek/rtlwifi/rtl8192ce/rtl8192ce.ko"]="/system/lib/modules/8192ce.ko"
    ["/usr/lib/modules/$kernel_version/kernel/drivers/net/wireless/realtek/rtlwifi/rtl8821ae/rtl8821ae.ko"]="/system/lib/modules/8821ae.ko"
)

for source_file in "${!symlinks[@]}"; do
    link_name="${symlinks[$source_file]}"
    if create_mod_symlink "$source_file" "$link_name"; then
        echo "Symbolic link created: $link_name ->$source_file"
    else
        echo "Failed to create symbolic link: $link_name ->$source_file"
    fi
done

COMPATIBLE=$(cat /proc/device-tree/compatible)
if [[ $COMPATIBLE =~ "rk3288" ]];
then
    CHIPNAME="rk3288"
elif [[ $COMPATIBLE =~ "rk3328" ]]; then
    CHIPNAME="rk3328"
elif [[ $COMPATIBLE =~ "rk3399" && $COMPATIBLE =~ "rk3399pro" ]]; then
    CHIPNAME="rk3399pro"
    update_npu_fw
elif [[ $COMPATIBLE =~ "rk3399" ]]; then
    CHIPNAME="rk3399"
elif [[ $COMPATIBLE =~ "rk3326" ]]; then
    CHIPNAME="rk3326"
elif [[ $COMPATIBLE =~ "px30" ]]; then
    CHIPNAME="px30"
elif [[ $COMPATIBLE =~ "rk3128" ]]; then
    CHIPNAME="rk3128"
elif [[ $COMPATIBLE =~ "rk3566" ]]; then
    CHIPNAME="rk3566"
elif [[ $COMPATIBLE =~ "rk3568" ]]; then
    CHIPNAME="rk3568"
elif [[ $COMPATIBLE =~ "rk3588" ]]; then
    CHIPNAME="rk3588"
else
    CHIPNAME="rk3036"
fi
COMPATIBLE=${COMPATIBLE#rockchip,}
BOARDNAME=${COMPATIBLE%%rockchip,*}

# init rkwifibt
init_rkwifibt ${CHIPNAME}
