#!/bin/bash

# ============================================================
# ImmortalWrt 每周编译启动器
#
# 运行用户：
#   op
#
# tmux session：
#   op
#
# ============================================================


SESSION="op"

RUN_SCRIPT="$HOME/weekly-build-run.sh"

RUNNING_FILE="$HOME/.weekly-build.running"


# ============================================================
# 检查运行脚本
# ============================================================

if [ ! -x "$RUN_SCRIPT" ]; then
    echo "ERROR: $RUN_SCRIPT 不存在或没有执行权限"
    exit 1
fi


# ============================================================
# 检查 immortalwrt
# ============================================================

if [ ! -d "$HOME/immortalwrt" ]; then
    echo "ERROR: $HOME/immortalwrt 不存在"
    exit 1
fi


# ============================================================
# 检查上一次编译是否仍然运行
# ============================================================

if [ -f "$RUNNING_FILE" ]; then

    RUNNING_PID=$(cat "$RUNNING_FILE" 2>/dev/null || true)

    if [ -n "$RUNNING_PID" ] && kill -0 "$RUNNING_PID" 2>/dev/null; then

        echo "上一次 ImmortalWrt 编译仍在运行"
        echo "PID: $RUNNING_PID"
        echo "不启动新的编译任务"

        exit 0
    fi


    # --------------------------------------------------------
    # PID 已不存在
    #
    # 说明：
    #   - 上一次编译已经结束
    #   - 或者服务器重启过
    # --------------------------------------------------------

    echo "发现旧的运行状态，但 PID 已不存在"
    echo "清理旧状态文件"

    rm -f "$RUNNING_FILE"

fi


# ============================================================
# 检查 tmux op
# ============================================================

if ! tmux has-session -t "$SESSION" 2>/dev/null; then

    echo "tmux $SESSION 不存在，创建新的 tmux session"

    tmux new-session -d -s "$SESSION"

fi


# ============================================================
# 启动编译
# ============================================================

echo "启动 ImmortalWrt 编译"

tmux send-keys -t "$SESSION" \
    "bash \"$RUN_SCRIPT\"" C-m


echo "编译任务已经启动"
