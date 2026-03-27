#!/bin/bash
# 文件：/usr/local/bin/monitor-bluetooth.sh

LOCK_FILE="/tmp/bt_monitor.lock"
SERVICE="wifibt-init.service"
HCI_DEV="hci0"
COOLDOWN=15  # 需大于服务初始化时间（含5秒延时）

cleanup() {
    rm -f "$LOCK_FILE"
    logger "[BT] 清理锁文件"
}
trap cleanup EXIT INT TERM

# 原子锁检查
if [[ -f "$LOCK_FILE" ]]; then
    if [[ $(($(date +%s) - $(stat -c %Y "$LOCK_FILE"))) -lt $COOLDOWN ]]; then
        logger "[BT] 冷却中，跳过"
        exit 0
    fi
    # 检查服务是否仍在运行
    if systemctl is-active --quiet "$SERVICE"; then
        logger "[BT] 服务仍在激活状态"
        exit 0
    fi
fi

# 创建新锁文件
touch "$LOCK_FILE"

# 增强型服务重启
restart_service() {
    logger "[BT] 执行深度恢复..."
    
    # 第一阶段：服务重启
    if ! systemctl restart "$SERVICE"; then
        logger "[BT] 服务重启失败！尝试硬重置..."
        {
            hciconfig "$HCI_DEV" down
            sleep 2
            systemctl reset-failed "$SERVICE"
            systemctl restart "$SERVICE"
        } >/dev/null 2>&1
    fi

    # 第二阶段：接口状态验证
    for ((i=1; i<=5; i++)); do
        if hciconfig "$HCI_DEV" | grep -q "UP"; then
            logger "[BT] 恢复成功 (${i}s)"
            return 0
        fi
        sleep 1
    done
    
    logger "[BT] 严重错误：恢复失败！"
    return 1
}

# 主检测逻辑
for ((attempt=1; attempt<=3; attempt++)); do
    if ! hciconfig "$HCI_DEV" | grep -q "UP"; then
        logger "[BT] 检测到DOWN状态 (尝试 ${attempt}/3)"
        
        # 延迟二次确认
        sleep $((attempt * 2))
        if hciconfig "$HCI_DEV" | grep -q "UP"; then
            logger "[BT] 状态已自动恢复"
            exit 0
        fi
        
        # 触发恢复流程
        if restart_service; then
            exit 0
        fi
    else
        logger "[BT] 状态正常"
        exit 0
    fi
done

logger "[BT] 达到最大尝试次数"
exit 1