#!/data/data/com.termux/files/usr/bin/bash
# dt — Termux 桌面开关
# 用法: dt on | dt off | dt status

VNC_DISPLAY=":1"
VNC_PORT=5901

# 检测方式：直接读 /proc/*/comm。
# 原因：本机 Termux 的 pgrep 有 bug —— 对 comm == "Xvnc" 的进程，
# `pgrep -x Xvnc` 返回空（但 /proc/<pid>/comm 明确写着 Xvnc）。
# 另外 pgrep -f 会匹配到调用它的 ssh/bash 自身命令行，造成假阳性。
vnc_pids() {
    local d pid comm
    for d in /proc/[0-9]*; do
        pid="${d#/proc/}"
        comm=""
        [ -r "$d/comm" ] && read -r comm < "$d/comm" 2>/dev/null
        case "$comm" in
            Xvnc|Xtigervnc) echo "$pid" ;;
        esac
    done
}

vnc_running() {
    [ -n "$(vnc_pids)" ]
}

# 优先取 wlan0 的局域网地址；没有则退回 Tailscale 的 tun 地址。
get_ip() {
    local out
    out="$(ifconfig 2>/dev/null)"
    local wifi ts
    wifi="$(echo "$out" | awk '/^wlan0:/{f=1} f&&/inet /{print $2; exit}')"
    ts="$(echo "$out" | awk '/^tun[0-9]*:/{f=1} f&&/inet /{print $2; exit}')"
    echo "${wifi:-${ts:-<无网络>}}"
}

clean_stale() {
    rm -f "$PREFIX/tmp/.X1-lock" \
          "$PREFIX/tmp/.X11-unix/X1" \
          "$HOME/.vnc/localhost:1.pid" 2>/dev/null
}

show_status() {
    echo ""
    if vnc_running; then
        echo "  🖥️  图形桌面：✅ 运行中"
        echo ""
        echo "      局域网：$(get_ip):${VNC_PORT}"
        echo "      Tailscale：$(ifconfig 2>/dev/null | awk '/^tun[0-9]*:/{f=1} f&&/inet /{print $2; exit}'):${VNC_PORT}"
        echo "      分辨率：1920x1080"
        echo ""
        echo "      关闭：dt off"
    else
        echo "  🖥️  图形桌面：⭕ 未运行"
        echo ""
        echo "      开启：dt on"
    fi
    echo ""
}

case "${1:-status}" in
    on)
        if vnc_running; then
            echo "✅ 桌面已经在运行了"
            show_status
            exit 0
        fi
        clean_stale
        export DISPLAY="${VNC_DISPLAY}"
        termux-wake-lock 2>/dev/null
        vncserver "${VNC_DISPLAY}" -geometry 1920x1080 -depth 24 -localhost no >/dev/null 2>&1
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            vnc_running && break
            sleep 1
        done
        if vnc_running; then
            echo "✅ 桌面已启动"
            show_status
        else
            echo "❌ 启动失败，最后 15 行日志："
            tail -15 "$HOME/.vnc/localhost${VNC_DISPLAY}.log" 2>/dev/null
            exit 1
        fi
        ;;
    off)
        if ! vnc_running; then
            echo "⭕ 桌面本来就没在运行"
            clean_stale
            exit 0
        fi
        vncserver -kill "${VNC_DISPLAY}" >/dev/null 2>&1
        for p in $(vnc_pids); do kill "$p" 2>/dev/null; done
        sleep 1
        for p in $(vnc_pids); do kill -9 "$p" 2>/dev/null; done
        pkill -f xfce4-session 2>/dev/null
        sleep 1
        clean_stale
        termux-wake-unlock 2>/dev/null
        echo "✅ 桌面已关闭"
        ;;
    status)
        show_status
        ;;
    *)
        echo "用法: dt [on|off|status]"
        echo ""
        echo "  dt 或 dt status   查看桌面状态"
        echo "  dt on             启动图形桌面"
        echo "  dt off            关闭图形桌面"
        exit 1
        ;;
esac
