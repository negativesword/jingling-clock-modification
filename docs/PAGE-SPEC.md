# 页面规格（v23）

单文件 `clock.html`，目标设备固定 **1024×600 / Chrome 61 / 无键盘 / 触摸**。
所有尺寸按像素写死，不用 vw/vh、不用 flex `gap`、不用无前缀 `transform`。

---

## 1. 版式

### 1.1 页面骨架

```
#wrap{position:fixed;inset:0;overflow:hidden;background:#000}
#track{width:200%;display:flex}        ← 两页各 50%，横向滑动切换
  阈值 70px，动画 .42s cubic-bezier(.22,.61,.36,1)
#dots{position:fixed;bottom:20px;pointer-events:none}   ← 页码点，8×8，激活宽 20
```

### 1.2 时钟页

| 元素 | 位置 / 参数 |
| --- | --- |
| 卡片 | 258×258，圆角 30，容器 `top:171px; left:74px; right:74px`，相邻 `margin-right:41px` |
| 卡片渐变 | 10 个色标 `#272727 → #0B0B0B` + 竖向细纹 |
| 质感 | 五条 box-shadow；`.shade`（`top:50%`，z2，`pointer-events:none`）；`.seam`（`top:50%`、高 4px、z3） |
| 数字 | `sans-serif-condensed`，276px / 700 / `#D8D8D8` / `scaleX(.78)` / `tabular-nums`，z1 |
| 顶行 · 星期 | `.day-line`：`top:74px; left:44px`，26px，`#8E8E8E`，字距 1px，文本「星期六」；`tick()` 里 `dayShown` 守卫，变了才写 |
| 顶行 · 日期 | `.date-line`：`top:74px; left:0; right:0; text-align:center`，26px，`#8E8E8E`，字距 1px，格式 `2026年11月14日`（只有公历，无农历） |
| 顶行 · 周数 | `.week-line`：`top:74px; right:44px`，26px，`#8E8E8E`，字距 1px，文本「第 46 周」；与左端 `left:44px` 对称，`tick()` 里 `weekShown` 守卫 |
| 倒计时状态行 | `.cd-status`：`top:456px; height:44px; line-height:44px`，z6，整行热区；空闲 19px `#8E8E8E`，运行/最后一分钟/到点共用 `.cd-status.run`：30px / `#EDEDED` / 600 / 字距 3px / `tabular-nums`，文本前缀 `⌛ `（`U+231B`） |
| 倒计时底条 | `.cd-status.run::before`（含 `.final10` / `.done`）：320×46 圆角 10、水平居中、`z-index:-1`、`background:rgba(255,255,255,.08)`——只提亮不抢戏，空闲态不绘制 |
| 公司名 | `.caption`：`top:505px`，24px，`#9C9C9C`，字距 4px，`line-height:28px`，`pointer-events:none`，文案「×××」 |
| 左下快捷图标组 | `#cdQuick`：`left:16px; top:489px; z-index:20; height:60px`；`.icbtn` 84×60，间距 6；svg 40px，`margin-top:10px`，描边 `rgba(255,255,255,.40)` |
| 番茄入口 | `#pomoBtn`：`right:16px; top:489px; 84×60; z-index:20`，🍅 34px，`grayscale(.15)` |

> **图标一定要 `pointer-events:none`**：`#cdQuick svg, #cdQuick svg *{pointer-events:none}`，否则空心圆环内部点不动。

### 1.3 倒计时面板 `#cdPanel`

全屏 `#000`，`display:none`，`z-index:20`，`.on` 生效。**没有"点空白处关闭"的绑定**——退出一律走「取消 / 关闭」，否则会吃掉打开它的那次点击。

| 元素 | 参数 |
| --- | --- |
| 标题 `.cd-title` | `margin-top:88px`，19px，`#777`，字距 6px |
| 大字 `.cd-big` | 132px，`scaleX(.86)`；运行模式 `margin-top:60px` |
| 滚轮 `.cd-wheels` | 510×154，`margin:28px auto 0`；`.wbar` `top:66px; height:44px`，`#262626`，圆角 12 |
| 滚轮列 `.wcol` | 宽 170，left 0 / 170 / 340；`.wcap` 22px/14px `#6E6E6E`；`.wview` 132px；`.witem` 行高 44，字 26px `#7E7E7E`，选中 `#F2F2F2` 600 |
| 快捷格 | `.cd-chip` 150×38 圆角 10，`margin:0 6px`，18px `#AEAEAE`，底 `#191919`；选中 `#2E2E2E/#F0F0F0`；保存闪一下 `#3A3A3A/#FFFFFF` 1.5s；整排 798px 居中，y=341 |
| 提示行 `.cd-hint` | `margin-top:14px`，15px `#575757`：「点＝选用　按住约 0.7 秒＝把当前时长存到这一格」 |
| 铃声行 `.cd-ring` | `.r-btn` 38×38；`.r-name` `min-width:112px`、17px `#D0D0D0`；`.r-try` 高 38、15px、底 `#101010` + `1px #2A2A2A` |
| 动作行 `.cd-actions` | `margin-top:18px`（运行模式 80px）；`.cd-act` 150×52 圆角 26，21px；`.main` 白底 `#E6E6E6` 黑字 |

滚轮实现要点：`ROW=44`，`value()=idx%count`（无限循环），`paint()` 用 `translateY(ROW - idx*ROW)` 定位当前行，`set(v){idx = count + v}`。

### 1.4 番茄钟 `#pomoPanel` / `#pmCfgBox`

配色取 pomofocus：专注 `#BA4949`、短休 `#38858A`、长休 `#397097`。

| 元素 | 参数 |
| --- | --- |
| 页签 `.pm-mode` | 150×50，21px，y=109（番茄钟 350 / 短休 512 / 长休 674） |
| 大字 `.pm-time` | 160px，行高 176 |
| 轮次 | 30px，🍅 一排 |
| 按钮 `.pm-act` | 高 58，圆角 29，22px，y=445（开始 315 / 重置 435 / 设置 555 / 返回 675） |
| 提示行 | 15px |
| 设置页 | 行高 48，步进键 48×48，标题 21px；`−` x=512、`+` x=661，y=118/176/234/292；自动 `(592,352)`、清零 `(626,414)`、完成 `(512,503)` |

**白底主按钮在彩色页面上必须显式补字色**，否则设置页「完成」是白字白底：
```css
.pm-act.main{background:#E6E6E6;color:#1A1A1A}
#pmCfgBox.focus .pm-act.main{color:#BA4949}
#pmCfgBox.short .pm-act.main{color:#38858A}
#pmCfgBox.long  .pm-act.main{color:#397097}
```

---

## 2. 实测点击坐标（1024×600）

| 目标 | 坐标 |
| --- | --- |
| ▶ 直接起跑 | (58,519) |
| ■ 停止 | (148,519) |
| ⏱ 打开倒计时面板 | (238,519) |
| 🍅 打开番茄面板 | (966,519) |
| 时钟页倒计时状态行 | (512,484) 或 (512,490) |
| 滚轮列中心 | 时 342 / 分 512 / 秒 682；中心行 y=234（上行 190，下行 278） |
| 快捷格 | x=188/350/512/674/836，y=341 |
| 倒计时设定模式 | 开始 (427,497)、取消 (597,497) |
| 倒计时运行模式 | 停止 (427,408)、关闭 (597,408) |
| 铃声行 y≈432 | ‹ (388,432)、名称 (466,432)、› (552,432)、试听 (618,432) |
| 番茄页签 y=109 | (350,109)/(512,109)/(674,109) |
| 番茄按钮 y=445 | 开始 315 / 重置 435 / 设置 555 / 返回 675 |
| 滑动切页 | 左滑 `input swipe 860 300 180 300 240`；右滑反向 |

> 这些坐标是给 `adb shell input tap` 自动化回归用的。**改了任何字号/间距，坐标必须重测**——v22 放大番茄界面时所有点位整体位移过一次。

---

## 3. 状态与存储

| 键 | 内容 | 备注 |
| --- | --- | --- |
| `cdSlots_v1` | 5 个快捷档的秒数数组 | 默认 `[60,300,600,1800,3600]`；长按写入当前时长 |
| `cdRing_v1` | 铃声**索引** | 顺序敏感：调整 `RINGS` 顺序会让旧值指错铃声（未修，勿随意重排） |
| `pomo_s1` | `{cfg, pm}` | 存**绝对结束时间戳**，重载/断电按剩余时间续算 |

番茄默认 `pmCfg = {focus:25, short:5, long:15, gap:4, auto:true}`，`pm = {mode:'focus', left:1500, end:0, running:false, round:0}`。
状态机：`专注 → round++ → (round % gap == 0 ? 长休 : 短休) → 专注`；到点响 6 秒后切段，`auto` 为真则立刻接力。

---

## 4. 函数地图

**倒计时 / 铃声 / 滚轮**
`cdLoadSlots` `cdSaveSlots` `cdHMS` `cdChipLabel` `cdFmt` `cdRemain` `cdRender` `cdQuickState` `cdStart` `cdStop`
`audioInit` `audioWake` `beep` `beepLoop` `ringDecode` `ringPlayLoop` `ringPrepare` `ringPlay` `ringStop` `alarmStart` `alarmStop`
`Wheel` `wheelTotal` `cdSetWheels` `cdWheelsChanged` `cdBuildChips` `cdRingState` `cdLoadRing` `cdSaveRing` `cdRingStep` `cdRingTry`
`cdOpen` `cdClose` `qbind`

`cdStop()` 顺序固定：`alarmStop(); cdRunning=false; cdDone=false; cdEnd=0; cdRender();`

**番茄钟**
`pmInit`（内部 `H = window.PM_HOOK`）`pmDur` `pmFmt` `pmNow` `pmLoad` `pmSave` `pmPaint` `pmStart` `pmPause` `pmReset` `pmSwitch`
`pmRingStop` `pmChime` `pmNext` `pmTick` `pmOpen` `pmClose` `pmCfgPaint` `pmHint` `pmStep`

**跨 `<script>` 块桥接**（主脚本块尾部）：
```js
window.PM_HOOK = { qbind, pad, audioWake, ringPrepare, ringPlay, ringStop };
```
番茄钟模块里用 `var H = window.PM_HOOK;` 取别名——**同一文件里另一段 `<script>` 的顶层函数不可见**。

**时钟 / 日历**
`tick`（每秒一次：日期、星期、周数、月份变化时才重排日历）`renderCalendar` `isoWeek`（ISO 8601 周数，日历页「第 N 周」同源）
`tick()` 内三处忠实于「变了才写 DOM」：`dateLine` 每秒重拼公历字符串、`dayShown` 与 `weekShown` 两个变量分别守住星期与周数，`calKey` 守住整月重算。

**初始化**：整个番茄模块包进 `pmInit()`，并
```js
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', pmInit, false);
else pmInit();
```
5MB 页面下 `setTimeout(fn, 0)` 不保证在 DOM 就绪后触发。

---

## 5. 两个关键防护

```js
// ① 面板关闭后挡迟到的合成 click（v22b）
window.PM_CLOSE_T = +new Date();                                  // pmClose 里
if (+new Date() - (window.PM_CLOSE_T || 0) < 700) return;         // cdOpen 开头

// ② 面板打开时藏掉同层图标，避免叠影
document.getElementById('pomoBtn').style.visibility = 'hidden';   // cdOpen
document.getElementById('pomoBtn').style.visibility = '';         // cdClose
```

---

## 6. 页面体积

| 版本 | 体积 | 构成 | 首渲 |
| --- | --- | --- | --- |
| 真机 v23（自用，含倒计时持久化） | 5,515,727 B / md5 `921b5097…` | 代码 ~40KB + 七首 iOS 铃声 base64 | 32~38 秒 |
| 仓库版（本仓库 `page/index.html`） | 240,070 B / md5 `d25b6c44…` | 代码 ~40KB + 一段自制合成提示音 base64（187,792 B） | 约 8~10 秒 |

体积直接决定首渲时间，而首渲时间又决定"force-stop 之后要等多久再截图"：5.5MB 版本必须等 32 秒以上，240KB 版本 8~10 秒就够。旧的 v22b 在 1GB 机器上实测 kiosk `VmRSS 162 MB / VmHWM 173 MB`，系统 `MemAvailable 486,856 kB`——内存不是瓶颈，**首渲耗时才是**。

只放代码、一段音频都不内嵌时页面约 40KB；到点仍会响，走的是 `beepLoop()` 的 WebAudio 振荡兜底。要更多铃声就按 `tools/pack_ringtones.py` 内嵌自有音频，并接受体积回到 MB 量级、首渲变慢。
