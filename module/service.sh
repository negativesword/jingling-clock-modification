#!/system/bin/sh
# Magisk 开机服务：看门狗
#   20s 判活：进程不在就拉起
#   60s 判前台：当前 resumed activity 不是 kiosk 就拉回
#   每日凌晨重载一次：WebView 堆跑满一天后，1GB 机器会把它的活页换进 zram，
#   页面每秒刷新都要从 zram 解压（major fault），内核态 CPU 被打满，整机变卡。
#   重载期间页面空白约 30 秒，所以只放在凌晨窗口；若连续 30 小时没能重载
#   （例如凌晨窗口被错过），则不再挑时段，立即重载。
# 参考实现（按公开逻辑整理），上线前请按 module/README.md 的步骤自测一遍。

PKG=uk.nktnet.webviewkiosk
ACT=$PKG/.MainActivity
LOG=/data/local/tmp/infoscreen.log
TMP=/data/local/tmp/.infoscreen_probe
STAMP=/data/local/tmp/kiosk_started

MIN_AGE_H=6      # 距上次重载至少 6 小时，避免刚拉起就又被重载
HARD_H=30        # 30 小时没重载过就无条件重载
NIGHT_FROM=3     # 凌晨窗口起点（设备本地小时）
NIGHT_TO=5       # 凌晨窗口终点（不含）

log() { echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"; }

# 拉起并把“本次启动时刻”落盘，供重载判定使用
launch() {
  am start -n "$ACT" > /dev/null 2>&1
  date +%s > "$STAMP" 2>/dev/null
}

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

# 是否到重载时间（返回 0 表示该重载）
reload_due() {
  now=$(date +%s)
  st=$(cat "$STAMP" 2>/dev/null)
  if [ -z "$st" ]; then date +%s > "$STAMP"; st=$now; fi
  age_h=$(( (now - st) / 3600 ))
  # 用 epoch 直接算本地小时（UTC+8），避开 date +%H 生成 08/09 被当八进制的坑
  hour=$(( ((now + 28800) % 86400) / 3600 ))
  [ "$age_h" -ge "$HARD_H" ] && return 0
  if [ "$age_h" -ge "$MIN_AGE_H" ] && [ "$hour" -ge "$NIGHT_FROM" ] && [ "$hour" -lt "$NIGHT_TO" ]; then
    return 0
  fi
  return 1
}

i=0
log "watchdog start"
while true; do
  if ! pidof "$PKG" > /dev/null 2>&1; then
    log "not running -> start"
    launch
    # 冷启动给足首渲时间，避免刚起又被判死
    sleep 8
  fi

  # 每 3 个循环（约 60s）检查一次：先判重载，再判前台
  i=$((i + 1))
  if [ $((i % 3)) -eq 0 ]; then
    if reload_due; then
      log "scheduled reload"
      am force-stop "$PKG" > /dev/null 2>&1
      sleep 3
      launch
      i=0
      trim_log
      sleep 20
      continue
    fi
    if ! foreground_is_kiosk; then
      log "not foreground -> bring to front"
      am start -n "$ACT" > /dev/null 2>&1
    fi
  fi

  trim_log
  sleep 20
done
