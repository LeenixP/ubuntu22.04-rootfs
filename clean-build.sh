#!/bin/bash -e
set -o errexit -o nounset -o pipefail

LOG_FILE="clean-build.log"

if [[ -e $LOG_FILE ]]; then
    echo "[$(date '+%F %T')] Removing $LOG_FILE"
    sudo rm -rf $LOG_FILE
fi

exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo "[$(date "+%F %T")] Error at line $LINENO" | tee -a "$LOG_FILE"; exit 1' ERR

declare -a MOUNT_POINTS=("binary/proc" "binary/sys" "binary/dev/pts" "binary/dev" "rootfs")
declare -a DELETE_TARGETS=("binary" "rootfs" 
                          "ubuntu-base-22.04.5-base-arm64.tar.gz" 
                          "ubuntu22.04.5-base-arm64-console.tar.gz" 
                          "ubuntu22.04.5-base-arm64-desktop.tar.gz" 
                          "ubuntu-jammy.img")

# 并行卸载函数
parallel_umount() {
    local mp=$1
    if mountpoint -q "$mp"; then
        echo "[$(date '+%F %T')] Unmounting $mp"
        sudo umount "$mp"
    fi
}
export -f parallel_umount

main() {
    echo "[$(date '+%F %T')] Starting cleanup"
    
    # 并行卸载挂载点
    parallel --jobs 200% --halt soon,fail=1 parallel_umount ::: "${MOUNT_POINTS[@]}"
    
    # 批量删除操作
    for target in "${DELETE_TARGETS[@]}"; do
        if [[ -e $target ]]; then
            echo "[$(date '+%F %T')] Removing $target"
            sudo rm -rf $target
        fi
    done
    
    # 内存加速清理
    local tmpfs_cleanup=$(mktemp -d -p /dev/shm)
    find . -maxdepth 1 -type f -name "*.tmp" -exec mv {} "$tmpfs_cleanup" \;
    sudo rm -rf "$tmpfs_cleanup"

    echo "[$(date '+%F %T')] Cleanup completed"
}

main "$@"