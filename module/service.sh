#!/system/bin/sh
# Magisk 开机服务：看门狗
#   20s 判活：进程不在就拉起
#   60s 判前台：当前 resumed activity 不是 kiosk 就拉回
#   重载：WebView 堆长跑会单调爬升（实测 21–24 MB/h，无平台期），1GB 机器把它的活页换进
#   zram，页面每秒刷新都要从 zram 解压（major fault），内核态 CPU 被打满、整机变卡。
#   v24 页面只有 53KB，重载白屏 2.8–3.0 秒，所以现在一天重载两次：
#     ① 22:00–22:20  ② 07:40–08:00
#   **08:00–22:00 一律不重载**（用户要求白天画面不许闪）。
#   例外只有“硬兜底”：超过 HARD_H 小时没重载过，且当前落在允许窗口内，才补一次。
#   （不设“不限时段”的兜底——任何按小时数触发的兜底都会落到白天，违反上面的规则。）
# 参考实现（按公开逻辑整理），上线前请按 module/README.md 的步骤自测一遍。
#
# 自测：sh service.sh --test-due <epoch>   # 只打印判定，返回 0=该重载 / 1=不重载

PKG=uk.nktnet.webviewkiosk
ACT=$PKG/.MainActivity
LOG=/data/local/tmp/infoscreen.log
TMP=/data/local/tmp/.infoscreen_probe
STAMP=/data/local/tmp/kiosk_started

MIN_AGE_H=4      # 距上次重载至少 4 小时，避免刚拉起就又被重载
HARD_H=26        # 26 小时没重载过，则在允许窗口内补一次（正常情况下永远触发不到）
EVEN_H=22        # 触发点一：22 点
EVEN_WIN=20      #        22:00–22:19 内允许
MORN_H=7         # 触发点二：07 点
MORN_FROM=40     #        07:40–07:59 内允许（08:00 起为禁止时段）
# 禁止窗口 = [08:00, 22:00)；允许窗口 = 22:00–08:00

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

# 是否到重载时间（返回 0 表示该重载）；$1 可传 epoch 用于自测
reload_due() {
  nows=${1:-$(date +%s)}
  st=$(cat "${STAMP_TEST:-$STAMP}" 2>/dev/null)
  if [ -z "$st" ]; then date +%s > "$STAMP"; st=$nows; fi
  age_h=$(( (nows - st) / 3600 ))
  # 用 epoch 直接算本地时刻（UTC+8），避开 date +%H 生成 08/09 被当八进制的坑
  sod=$(( (nows + 28800) % 86400 ))
  hot=$(( sod / 3600 ))
  mi=$(( (sod % 3600) / 60 ))

  # 硬兜底：超期且已在允许窗口（22:00–08:00）内才补
  if [ "$age_h" -ge "$HARD_H" ]; then
    if [ "$hot" -ge "$EVEN_H" ] || [ "$hot" -lt "$MORN_H" ]; then
      return 0
    fi
    return 1
  fi

  [ "$age_h" -ge "$MIN_AGE_H" ] || return 1

  # 触发点一：22:00–22:19
  if [ "$hot" -eq "$EVEN_H" ] && [ "$mi" -lt "$EVEN_WIN" ]; then return 0; fi
  # 触发点二：07:40–07:59
  if [ "$hot" -eq "$MORN_H" ] && [ "$mi" -ge "$MORN_FROM" ]; then return 0; fi

  return 1
}

if [ "$1" = "--test-due" ]; then
  reload_due "$2"
  exit $?
fi

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
