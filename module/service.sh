#!/system/bin/sh
# Magisk 开机服务：看门狗
#   20s 判活：进程不在就拉起
#   60s 判前台：当前 resumed activity 不是 kiosk 就拉回
# 参考实现（按公开逻辑整理），上线前请按 module/README.md 的步骤自测一遍。

PKG=uk.nktnet.webviewkiosk
ACT=$PKG/.MainActivity
LOG=/data/local/tmp/infoscreen.log
TMP=/data/local/tmp/.infoscreen_probe

log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"; }

# 日志滚动：超过 512 行留后 200 行
trim_log() {
  [ -f "$LOG" ] || return 0
  n=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
  if [ -n "$n" ] && [ "$n" -gt 512 ]; then
    tail -n 200 "$LOG" > "$TMP" 2>/dev/null && cat "$TMP" > "$LOG"
  fi
}

# 前台判定：先落盘再 grep，避免 dumpsys 的 SIGPIPE 把进程带崩
foreground_is_kiosk() {
  dumpsys activity activities > "$TMP" 2>/dev/null
  line=$(grep -m1 'mResumedActivity' "$TMP" 2>/dev/null)
  case "$line" in
    *"$PKG/"*) return 0 ;;
    *)         return 1 ;;
  esac
}

i=0
log "watchdog start"
while true; do
  if ! pidof "$PKG" > /dev/null 2>&1; then
    log "not running -> start"
    am start -n "$ACT" > /dev/null 2>&1
    # 冷启动给足首渲时间，避免刚起又被判死
    sleep 8
  fi

  # 每 3 个循环（约 60s）做一次前台判定
  i=$((i + 1))
  if [ $((i % 3)) -eq 0 ] && ! foreground_is_kiosk; then
    log "not foreground -> bring to front"
    am start -n "$ACT" > /dev/null 2>&1
  fi

  trim_log
  sleep 20
done
