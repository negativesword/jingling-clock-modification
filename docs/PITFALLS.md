# 踩坑清单

按主题分组。每条都是**实机踩到、定位到根因、修好并复测**的，不是猜测。括号里标了适用面（设备层 / 页面层）。

---

## A. 设备与系统层

### A1. 改 `/system` 一个字节就卡 logo（设备层）

**现象**：改完 system/vendor 里任何文件，重启卡在开机 logo，`dmesg` 刷 `dm-verity` EIO。
**根因**：MTK 默认开 dm-verity，system/vendor 有完整性校验。
**修法**：这条路直接放弃。所有系统侧改动走 **Magisk systemless**（只 patch boot.img，用 bind mount 覆盖上层文件）。判断"某个改动是否需要重启"的经验见 `magisk-systemless-file-edit-live-bind-mount`：**已存在文件的内容修改立即生效（bind mount），模块里新增文件不会热挂载**。

### A2. `pm disable-user` / `pm hide` 全部不可用（设备层）

**现象**：`pm disable-user` 报 `Error: unknown command`；某些机型上强用会立刻崩 `system_server`。
**修法**：下线预装应用改用**零字节占位 APK**（debloat 模块里放一个 0 字节的同名 apk，systemless 覆盖原包目录）。这条路可回滚、不动 `packages.xml`。
**注意**：`cmd package uninstall --user 0` 可用，但连打会 `Broken pipe (32)` 崩系统，不能批量。

### A3. HOME 键仍然回原厂桌面（设备层）

**现象**：`cmd package set-home-activity` 报 `Success`，但按 HOME 还是原厂桌面；软重启后有效、**冷启动又失效**。
**根因**：厂商定制机通常有**两个** HOME Activity——启动用的 `BootHomeActivity` 和主桌面 `AdultHomeActivity`，且 `preferred-activities.xml` 里的 match 值在冷启动时被重新计算。
**修法**（唯一稳定解）：在 `package-restrictions.xml` 的 `<disabled-components>` 里**组件级**禁用两个 HOME Activity，而不是改 preferred 或整包隐藏。
```xml
<disabled-components>
  <pkg name="com.alibaba.aliot.children">
    <disabled-component name="…launcher.activity.AdultHomeActivity"/>
  </pkg>
  <pkg name="com.alibaba.ailabs.genie.smartapp">
    <disabled-component name="…genieboot.activity.BootHomeActivity"/>
  </pkg>
</disabled-components>
```
改完必须补三件事，再软重启：
```bash
chown system:system /data/system/users/0/package-restrictions.xml
chmod 660 /data/system/users/0/package-restrictions.xml
chcon u:o:system_data_file:s0 /data/system/users/0/package-restrictions.xml
kill $(pidof system_server)      # 软重启；绝不能正常关机
```

### A4. 遮蔽 smartapp 后 SystemUI 崩溃-退避链（设备层）

**现象**：把 `com.alibaba.ailabs.genie.smartapp`（连同 `AliGenieService`、`GenieRTC`）用 0 字节占位遮蔽后，包确实从包管理器消失、内存与 CPU 都省下来了，但 `SystemUI` 开始周期性崩溃，间隔逐次拉长（1 → 2 → 4 分钟……），最后被 MTK AEE 计数到阈值整机重启。
**根因**：`SettingsProvider` / `SystemUI` 会 `query` 天猫精灵提供的 6 个 `ContentProvider` authority（`…genie.datacenter.DataCenterProvider` 等）。包没了，authority 无人声明，调用方不判空 → 崩。
**结论**：**能遮蔽，但必须先补 provider。** 自建一个 8.6 KB 的桩 APK（`com.zhu.geniestub`）声明这 6 个 authority、所有 `query` 返回空 `MatrixCursor`，装好后 SystemUI 不再崩。这套方案的完整步骤、残留告警与回滚见 [`SYSTEM-SLIMMING.md`](SYSTEM-SLIMMING.md)。

### A5. `adb pull` 直接崩（工具层，但影响所有取证）

**现象**：`adb pull` 报 `file_sync_client.cpp:477 protocol fault`，之后 push / pull / install 全崩，只能重插线。
**修法**：取文件一律
```bash
adb shell su -c "base64 <path>"
```
再在本地 `[Convert]::FromBase64String` 写盘。推文件同样走 base64：把整份 base64 从 stdin 喂给设备端 `base64 -d`（见 E6），**不要走 TCP + `nc` 那条回连通道**——它在连不上时会先把目标文件截成 0 字节。

### A6. 不能 `adb reboot`

**现象/约束**：安全策略硬阻断 `adb reboot`，只能物理断电或 `kill $(pidof system_server)` 软重启。
**影响**：验收冷启动必须靠拔电。

### A7. `suspend` 挡不住系统主动拉起的包（设备层）

**现象**：`cmd package suspend` 后 `dumpsys package` 里 `suspended=true` 仍在，但 `com.google.android.inputmethod.pinyin` 开机照旧占 **70 MB RSS**。
**根因**：suspend 只拦"自己想起床"的组件；输入法是系统里唯一注册的 IME，`InputMethodManager` 会把它的进程直接拉起。
**结论**：suspend 对普通应用有效、对系统必需角色无效。想省这 70 MB 只能换/删 IME，本机没做（信息屏用不到键盘，但也不想为一个用不到的功能改动输入法框架）。

### A8. 连跑一天以上整机变卡：zram 换页抖动（设备层）

**现象**（真机，连续开机 52.4 小时）：整机明显卡顿。`dumpsys cpuinfo` 显示 kiosk 占 **99% CPU，其中用户态只有 2.9%、内核态 96%**，累计 **major page fault 596 万次**；`kswapd0` 另占 46%。内存侧 `MemAvailable 306,312 kB`、`SwapFree` 只剩 **73,224 / 502,968 kB**（zram 已用约 85%），kiosk RSS 已涨到 **364,024 kB**。

**根因链**：WebView 堆在长跑中缓慢爬升（实测 0.3 h 时 174 MB → 7.2 h 317 MB → 52 h 364 MB，之后是 300–360 MB 的 GC 锯齿平台）→ 1 GB 内存装不下 → 内核把它的活页换进 zram → 页面每秒刷新要碰这些页 → 每次碰都要从 zram 解压（major fault）→ 运算全在内核态 → 4 核被 kiosk + kswapd 吃满 → 整机卡。**RSS 本身没到 OOM 线，卡在"换页"这一步**。

**判读注意（重要）**：这台机器的 `/proc/loadavg` 长期停在 **7.2–8.5**，因为它有 7 个常驻 D 态内核线程（`GCPU`、`hang_detect`、`entropy_thread`、`bat_thread_kthread`、`ion_history`、`fuse_log`、`display_esd_che`）。**loadavg 在这个设备上不能当卡顿指标**，要看 `dumpsys cpuinfo` 的 user/kernel 占比和 major fault 计数。整机 `idle` 也可以直接算 `/proc/stat` 两帧差。

**处置**：看门狗 `service.sh` 定时重载，两个触发点 22:00–22:19 与 07:40–07:59，`08:00–22:00` 一律不重载；`MIN_AGE_H=4` 防止刚拉起又被重载，`HARD_H=26` 只在允许窗口内补（不设"不限时段"兜底——按小时触发的兜底必然落到白天，违反窗口规则）。v24 把页面压到 53 KB 后重载白屏只有 2.8–3.0 秒，一天两次才可行；5.5 MB 母版时期是 30 秒，只能放凌晨一次。判定逻辑可用 `sh service.sh --test-due <epoch>` 单独验证。

**实测效果**（同一次处理，force-stop 前后 40 秒）：

| 指标 | 处理前 | 处理后 |
| --- | --- | --- |
| kiosk RSS | 364,024 kB | 157,704 kB |
| MemAvailable | 292,592 kB | 614,144 kB |
| zram 可换出 | 86,816 kB | 450,808 kB |
| kiosk CPU | 99%（内核态 96%） | 23%（用户态 19%） |
| 整机 CPU 空闲率 | — | 81.8% |

**flush 后的内存构成**（`dumpsys meminfo`，用来判断增长部位）：Java Heap 仅 4.5 MB、Native 10 MB、Code 49.5 MB、Graphics 19 MB、Private Other 48 MB、**Unknown 41.5 MB**。增长几乎全部落在 Chromium 的原生分配器与图形缓存（Unknown / Private Other / Graphics），**不是 JS 泄漏**——所以改页面代码省不下来，只能定期重载。

---

## B. WebView（Chrome 61）能力边界

这台机器的 WebView 是 `com.android.webview 61.0.3163.98`，以下都是**版本限制**，不是写错代码：

| 限制 | 后果 | 替代做法 |
| --- | --- | --- |
| 无 flex `gap` | 排间距失效 | 用 `margin` 手算 |
| `transform` 需前缀 | 无前缀写法被忽略 | `-webkit-transform: scaleX(.9)` |
| 无 `table-layout: fixed` 的现代行为 | 表宽塌成一字 | 显式 `table-layout:fixed` + `<colgroup>` 写死列宽 |
| `<audio>` / `new Audio()` 整条通道不可用 | 连系统自带 `Kuma.ogg` 都 `NotSupportedError` | 见 D 节 |
| 长按约 500ms 弹系统选字菜单 | `touchend` 被吞或延后 | 见 C3 |
| 多段 `<script>` 之间全局函数不共享 | 跨块调用报 `xxx is not defined` | 显式 `window.XXX = {…}` 桥接 |
| `setTimeout(fn, 0)` 在 5MB 页面不可靠 | 初始化时 DOM 还没就绪 | `DOMContentLoaded` + `readyState` 判断 |

### B1. "按钮存在、样式正常，但完全点不动"（页面层）

根因往往不是绑定位置，而是**初始化阶段抛异常整段没执行**：脚本排在面板 HTML 之前，`getElementById` 返回 `null`，`el.onclick = …` 抛错，后面的绑定和 `setInterval` 全没跑——页面其余动画照常，症状极具欺骗性。
修法：整个模块包进 `init()`，用
```js
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init, false);
else init();
```
在无调试通道的设备上取真实报错：临时挂 `window.onerror` 把消息追加进 `localStorage`，再
```bash
adb shell su -c "base64 '/data/data/<pkg>/app_webview/Local Storage/leveldb/000003.log'"
```
在本地解出 ASCII 段做正则。本次就是这样拿到 `Uncaught ReferenceError: qbind is not defined@1243` 的。

---

## C. 触摸、命中与手势

### C1. 空心 SVG 只有描边能点（页面层）

**现象**：同一排三个图标，实心的能点，空心圆环那个怎么点都没反应；点圆环边缘偶尔有反应。
**根因**：`pointer-events` 默认 `visiblePainted`，圆环内部空白不参与命中。
**修法**：让**父容器**接管命中
```css
#cdQuick svg, #cdQuick svg *{pointer-events:none;}
```

### C2. 全宽 fixed 覆盖层吃掉整条带（页面层）

**现象**：底部一行文字、四角按钮"看得见点不动"。
**根因**：某个 `left:0;right:0` 的 fixed 元素（哪怕 `opacity:0`、甚至只是空容器）在上层，命中测试归它。
**修法**：给纯展示层加 `pointer-events:none`，或把它移出热区带。顺带记住：`#cdStatus` 那种"整行热区"是**后面 C5 的罪魁**。

### C3. 长按"不是每次都生效"（页面层）

真实事件序列（从 localStorage 探针取回）：一次 800ms 长按 → `S3 → contextmenu@515ms → touchend@1207ms`，有时 `touchend` 干脆不来。
**三条根因**：① 系统长按菜单抢事件，旧逻辑全押 `touchend`；② 任何 `touchmove` 都取消，按住近 1 秒必然抖动→自我取消；③ 面板一次只允许存一格的状态锁。
**四条修法**：
```css
.chip{-webkit-user-select:none;user-select:none;-webkit-touch-callout:none;-webkit-tap-highlight-color:transparent;}
```
```js
chip.oncontextmenu = function(){ return false; };
// touchstart 起 650ms 定时器，到点即执行，不等松手；touchend 晚到再兜一次（用 touched 标记防重复）
// touchmove 只在位移 > 20px 时取消
// 删掉 slotLocked
```

### C4. 触摸"双通道"是必须的

这台机器上 `click` 与 `touchend` 会随机缺一路。所有入口统一：
```js
function qbind(el, fn){
  var last = 0;
  function fire(){ var now = +new Date(); if (now - last < 400) return; last = now; fn(); }
  el.onclick = fire;
  el.addEventListener('touchend', function(){ fire(); }, false);
}
```

### C5. 面板"返回"弹出另一个面板（页面层）

**现象**：番茄面板点「返回」，面板关了，但屏幕跳到倒计时设置页。
**根因**：`#cdStatus`（时钟页底部 `top:462、高 44、左右通宽`）的 `onclick = cdOpen`；「返回」按钮中心 y=445 正落在带内。touchend 先隐藏面板，随后迟到的合成 click 命中已暴露的 `#cdStatus`。
**修法**：关闭时打时间戳，`cdOpen` 丢弃 700ms 内的点击
```js
window.PM_CLOSE_T = +new Date();               // 面板关闭处
if (+new Date() - (window.PM_CLOSE_T || 0) < 700) return;   // cdOpen 开头
```
顺带修一个视觉问题：两个面板都 `z-index:20` 时，后来的元素按文档顺序画在上面（倒计时面板里会浮出 🍅）；面板打开时把 🍅 设 `visibility:hidden`，关闭时还原。

### C6. 面板不遮底：不能靠半透明

全屏面板一律纯色不透明（本机用 `#000` 或模式色），否则底下 276px 的数字会透出来形成叠影；面板打开时底层页面仍可滑动，需要单独的滑动手势闸门。

---

## D. 声音（本机最麻烦的一段）

### D1. 四条路三条全废

1. Magisk 模块里新增音频文件 → 不热挂载，`/system` 只读不能 mkdir，只能等重启。弃。
2. 应用私有目录写入 mp3，`new Audio()` → `NotSupportedError`；**换成系统自带 `/system/media/audio/ringtones/Kuma.ogg` 同样报错** → 说明不是权限也不是编码，是这个 WebView 的媒体加载通道整体不可用。弃。
3. `data:audio/mpeg;base64,…` 塞 `src` → 同样 `NotSupportedError`。弃。
4. **WebAudio `decodeAudioData` 可用**（探针打出 `RING_DECODE_OK 4.96 48000`）。采用。

### D2. 正确的出声姿势

```js
// 手势里必须同步 resume，否则 ctx 停在 suspended，源 start 了也不出声
function audioWake(){ if (!actx) audioInit(); if (actx.state !== 'running') actx.resume(); }
// 预解码（只在用户手势里做一次，缓存当前选中的那首）
function ringPrepare(ok, fail){ … ringDecode(idx, …) … }
// 播放：base64 → ArrayBuffer → decodeAudioData → AudioBufferSourceNode(loop) → destination
```

### D3. 听不到也要能证明在响

```bash
adb shell su -c 'dumpsys media.audio_flinger | grep -E "active|Tracks of which"'
# 出现 "3 Tracks of which 1 are active" 即确实有音轨在播
adb shell su -c 'dumpsys audio'      # 看 STREAM_MUSIC 未被静音
```

### D4. 兜底要有

到点逻辑：先试铃声，1.5s 内没拿到 buffer 就回落到 `beepLoop()`（880×2 + 1046Hz，2.5s 一轮、24 轮自停），另有 60s 总兜底停表。
**注意**：剥离内嵌铃声（发布版）后，倒计时有这个回落；番茄钟的 `pmChime()` 目前没有回落分支，需要自己补一行 `if (!ringSrc) beepLoop();`。

### D5. 刷新一下，倒计时就没了（页面层）

**现象**：在操作页误触重载、或看门狗 force-stop 后重开，正在跑的倒计时直接回到空闲。原话："操作界面不小心刷新会冲掉当前的倒计时"。
**根因**：`cdTotal / cdEnd / cdRunning / cdDone` 只活在内存里。页面是 `file://` 单文件，WebView 每次重载都会重跑一遍 IIFE，状态清零。番茄钟没这个问题——它早就把**绝对结束时刻**写进了 `localStorage`（`pomo_s1`）。
**修法**：照番茄钟的范式，把倒计时的绝对结束时刻落盘，键名 `cdState_v1`：

```js
function cdSaveState(){
  try {
    if (cdRunning && cdEnd > 0) {
      window.localStorage.setItem(CD_STATE_KEY, JSON.stringify({ end: cdEnd, total: cdTotal }));
    } else { window.localStorage.removeItem(CD_STATE_KEY); }
  } catch (e) {}
}
```

三个写入点：`cdStart()`（起跑落盘）、`tick()` 里到点翻成 `cdDone` 的那一瞬（此时 `cdRunning` 已为 false，等于清）、`cdStop()`（清）。

恢复函数 `cdRestoreState()` 放在初始化里、`tick()` 之前，三种情形分开处理：

| 重载时的情形 | 行为 |
| --- | --- |
| `end` 还没到 | 接着跑，剩余＝`end - now`，不重新计时 |
| `end` 已过但 ≤60s | 补成"时间到"并响一轮（避免"正好在重载期间到点"被吞掉） |
| `end` 已过 >60s | 清记录回空闲（防隔夜重载突然响铃） |

**为什么存绝对时刻而不是剩余秒数**：首渲本身要 14s（真机 5.5MB 版约 35s），存剩余秒数等于让这段空白白跑；`end` 是时间戳，重载耗多久都不影响精度。
**残留限制**：`cdRestoreState()` 里的 `alarmStart()` 可能因没有用户手势被 autoplay 策略拦掉——"时间到"一定显示，声音不一定有。这是 Chrome 61 的策略，不是逻辑错。

**真机验证（2026-11-09，正式 v22c `ca0236f1…`，1024×600）**：三条分支分开跑，取证不靠肉眼，而是临时注入 `cdLog()` 探针把事件写进 `localStorage['cdDbg']`（只进调试页，发布版不含探针），事后 `su -c cat` 取 `/data/data/uk.nktnet.webviewkiosk/app_webview/Local Storage/leveldb/000003.log` 解出时间戳。

| 实验 | 起跑 → 结束时刻 | 强杀落在 | 探针证据 | 屏幕 |
| --- | --- | --- | --- | --- |
| 生效前的失败样本 | 11:11:56，00:00:58 | `end` 之前 20s | 无（当时还没有探针） | 重载后整行空白 |
| ① 接着跑 | 11:18:08，60s | `end` 之前 15s | `R-running` → `tickdone`（`end`+0.8s） | 11:19:37 "时间到" |
| ② 到点在重载窗口内 | 11:37:35，60s | `end` 之前约 2s | `R-past-2976` → `R-done` | "时间到" |
| ③ 正式 v22c 真机复测 | 11:42:07，00:00:58 | 45s 后，重载约 35s | 同上分支（发布版无探针） | 11:43:41 "时间到" |

**声音**：②里在补响期间 `dumpsys media.audio_flinger` 的 `active track` 计数为 0——重载后补响确实不出声，与上面的 autoplay 残留限制一致，视觉提示照常。

**那次失败样本仍未解释**：唯一一次"整行空白"发生在探针接入之前；三条探针记录里都没有出现 `R-clear`，也没有出现第二次 `boot`，所以"到点后被二次重载清掉"只是猜测，不能当作结论。加探针后未再复现。

---

## E. 文件、编码与工具链

### E1. CRLF/LF 混排 → PowerShell 替换静默失效（工具层）

页面里既有 LF 又有 CRLF 时，here-string 里的多行片段对不上，`-replace` 一句不报错、也没改到。
**修法**：先 `$t = $t.Replace("\r\n","\n")` 统一成 LF，再用单行字符串做精确替换，最后一次 `[IO.File]::WriteAllText` + `new UTF8Encoding($false)` 写回；写完立刻用 `Select-String` 数命中次数验证真的改到了。

### E2. 大文件里的 base64 段不能整段读写

5.5MB 页面含七段 base64，任何"整文件正则替换"都可能误伤。
**修法**：只对非 base64 段做精确 `Replace`；需要改 `RINGS` 时用 `tools/pack_ringtones.py`（只匹配 `RINGS = [ … ];` 这一处）。

### E3. PowerShell 的几个必踩点

- `Substring($i, 1400 -replace ...)` 三参数写法报 `MethodException`——`Substring` 只接两参数。
- `su -c "pid=$(pidof ...)"` 里的 `$(` 会被 PowerShell 抢先求值——先 `pidof > /tmp/p.txt` 再 `cat`。
- 单引号里的反引号 `` `n `` 不转义——多行替换改用双引号或 here-string。
- 一次 `for` 循环连推 7 个文件会超 15s 前台等待被转后台，需要 `TaskOutput` 取结果。

### E4. 本机没有的工具（决定了方案边界）

无 java/javac/gradle/Android SDK、无 ffmpeg、无 PIL、无 Python `av`/`pydub`。
→ 音频只能**设备端 WebAudio 解码**，不能本地转码；图片裁切用 `Add-Type System.Drawing` + `Graphics.DrawImage`。

### E5. 参考图读取

base64 超过 5MiB 会被 Read 工具拒绝，先缩到 1400px 宽 JPEG q88 再看。

### E6. `adb push` 全崩 + `nc > 文件` 会把页面截成 0 字节（工具层，最贵的一次）

现象一：这台设备上 `adb push` / `adb pull` / `adb install` 一律崩在 `F adb.exe: file_sync_client.cpp:477 protocol fault: failed to read stat response`，连推一个 240KB 的文件也会崩。
现象二：改用"PC 起 TcpListener + 设备端 `su -c 'toybox nc <PC-IP> <port> > <目标文件>'`"回连时，如果设备连不到 PC（PC 换了网络、IP 从 `192.168.2.x` 变成手机热点/WARP 地址），设备侧的 shell 重定向**在连上之前就把目标文件截成 0 字节**了，页面直接变空白屏。`md5sum` 得到 `d41d8cd98f00b204e9800998ecf8427e`（空文件的 md5）就是它。

**修法**：

```powershell
# ① 最稳的传输：base64 走 adb shell 的 stdin，不依赖 PC 的 IP 和任何端口
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes('page/index.html'))
$b64 | & adb -s <device-ip>:5555 shell "su -c 'base64 -d > /data/local/tmp/new.html'"
& adb -s <device-ip>:5555 shell "su -c 'md5sum /data/local/tmp/new.html'"
# 确认 md5 与本地一致后再 cp 到模块目录
& adb -s <device-ip>:5555 shell "su -c 'cp /data/local/tmp/new.html /data/adb/modules/infoscreen/system/etc/clock.html'"
```

② **先写到 `/data/local/tmp`，核对 md5，再 `cp` 覆盖正式位置**。绝不要让正式文件成为传输的第一落点。
③ 既然 `/sdcard/clock/index.html` 里留了一份完整页面，**出事后就地恢复**：`su -c 'cp /sdcard/clock/index.html /data/adb/modules/infoscreen/system/etc/clock.html'`，几秒钟就能回到可用状态，不必等重新传 5MB。
④ 每次传完都 `md5sum` 对账——`nc`/重定向这类通道"命令成功返回"不代表字节到位。

### E7. 不要对模块内文件跑 `restorecon`（工具层，白屏事故）

**现象**：改完 `/data/adb/modules/infoscreen/system/etc/clock.html`，顺手 `restorecon` 想让 SELinux 标签"正确"，`am force-stop` 后 WebView 直接白屏，`logcat` 报 `ERR_FILE_NOT_FOUND`。
**根因**：`restorecon` 按**真实路径**（`/data/adb/modules/…`）去匹配策略，把文件标成 `u:object_r:adb_data_file:s0`。这个路径对 WebView 来说是 `/system/etc/clock.html`，标签不对就读不到。
**修法**：

```bash
su -c 'chcon u:object_r:system_file:s0 /data/adb/modules/infoscreen/system/etc/clock.html'
su -c 'ls -lZ /data/adb/modules/infoscreen/system/etc/clock.html'   # 与 /system/etc/hosts 的标签比对
```

用 `cat > 文件` 覆盖写可以保住 inode 与标签，所以日常改页面**不要删了重建**，直接 `cat` 覆盖。

---

## F. 调试纪律

- 探针一律"写 localStorage → 取 leveldb → 本地解码"，不依赖 logcat（本机 logcat 噪音大且常被厂商服务刷掉）。
- 收尾必须清零：删 `xxxDbg()`、删 `window.onerror` 钩子、删日志键。验证方式：`lpDbg` 与 `window.onerror` 都应为 0 处。
- **别用 `Dbg` 这个宽词去搜**：base64 音频串里可能正好出现 `Dbg` 三个字符，会给你一个假的"还有残留"。用带上下文的窄词（`lpDbg`、`pmDbg(`）才有意义。
- 每次改页面先复制到 `_backup/index-vNN-主题.html`，命名带主题，方便一屏找回"上次那个能用的版本"。

---

## G. 页面体积与铃声外置（v24）

### G1. 5.46 MB 内联 base64 = 每次重载 32–38 s

**现象**：`clock.html` 5,515,727 B，其中 7 段 `data:audio/mpeg;base64` 合计 **5,463,400 字符（99%）**，正文只有约 50 KB。`am force-stop` 到画面出现要 32–38 s，白天重载等于半小时白屏，所以只能一天重载一次——而内存增速 21–24 MB/h，一天一次根本撑不到傍晚。

**改法**：`RINGS` 只留名字（`{n:'倒影', d:''}`），音频切成 `rings/1.js … 7.js`，每个文件是 `window.RING_DATA=window.RING_DATA||{};window.RING_DATA[n-1]="data:audio/mpeg;base64,…";`。页面新增 `ringLoad(idx, cb)`：首次用到某铃声时才插 `<script>`，把 `window.RING_DATA[idx]` 收进 `RINGS[idx].d`，再走原 `atob → decodeAudioData`。

**结果（TG_S1，三次复测）**：页面 53,405 B，`am force-stop` → 画面刷新 **2.8 / 3.0 / 2.9 s**；试听时 `dumpsys media.audio_flinger` 的 track `Written` 由 84,224 帧涨到 150,784 帧，确认在播。

### G2. WebView 到底能读哪里（一条条试出来的）

| 路径 | 结果 | 原因 |
| --- | --- | --- |
| 同目录 `rings/N.js`（设备上是 `/system/etc/rings/`） | 重启后可用 | 模块新增文件要重启才挂载 |
| `file:///sdcard/Android/data/<pkg>/files/rings/N.js` | **可用（实测成功）** | App 自有外部目录，免存储权限 |
| `/sdcard/clock/rings/N.js` | 不可用 | kiosk 未授予 `READ_EXTERNAL_STORAGE`：`dumpsys package` 里只在 `requested permissions`，不在 `install/granted` |

所以"WebView 读不到 file://"这条旧结论要分情况：**XHR/fetch 读二进制是读不到的（铃声必须走 base64）**，但 `<script src>` 这种脚本加载可以，只要路径落在同目录或 App 自有外部目录。页面里因此写成两条候选路径，先同目录、再自有目录。

### G3. 设备侧切 base64：`printf` 会撞参数上限

**现象**：用 `printf 'prefix%s suffix' "$d"` 写 1.6 MB 的 base64，toybox 直接报 `Argument list too long`，7 个文件全是 62 字节的空壳。
**改法**：`echo` 是 shell 内建、不经过 argv 限制，配合 `cut` 取字段即可：

```sh
d=$(echo "$line" | cut -d"'" -f4)          # 第 4 个单引号分隔段 = data:audio/mpeg;base64,…
echo "window.RING_DATA=window.RING_DATA||{};window.RING_DATA[$i]=\"$d\";" > "$OUT/$i.js"
```

### G4. 替换 `];` 时留了两份闭合括号 → 整页不渲染，屏幕停在旧帧

**现象**：改完页面 `am force-stop` 后 `screencap` 连续两张 md5 完全相同，画面还是 11-08 的旧帧。这很容易被误读成"WebView 卡死 / 屏幕没刷新"，实际是**脚本语法错误导致页面根本没画出来**，SurfaceFlinger 一直显示上一帧。

**定位**：抽出最后一个 `<script>` 的内容跑 `node --check`，报 `Unexpected token ']'` —— 新块结尾的 `  ];` 和原块留下的 `  ];` 撞在一起变成 `];  ];`。

**规则**：
- 用 `IndexOf` 定位原块的 `  ];` 时，替换串已经自带 `];`，取后续内容必须从 `i2 + 4` 起跳，不能从 `i2` 起跳。
- 拼接完先 `node --check` 再上设备；屏幕"冻结"时第一件事是查语法，不是重启。
- `[regex]::Replace($text, {param($m) ...}, 1)` 在 PowerShell 7 里会**静默返回原文**（没报错、也没替换），别拿它做大文件手术；一律 `IndexOf` + `Substring`。
