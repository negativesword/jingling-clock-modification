# page/

`index.html` 就是页面本体：单文件、自包含、能在 Chrome 61（Android 8.1 WebView）上跑。把它推到设备上就是整块信息屏的全部 UI。

## 这一版里有什么

| 项 | 值 |
| --- | --- |
| 体积 | 53,495 B（**页面内已不含任何音频**，正文 + 样式 + 脚本） |
| MD5 | `5697d77e5589463a0b4daee4826bee7b` |
| 音频 | 在 `page/rings/1.js`（187,876 B / `81252d6f0e15f825baaa3e639019f754`），来自 `../assets/chime.wav` |
| 商业素材 | 无（七首 iOS 铃声已全部剔除） |
| 已验证 | 2026-11-09 推上 TG_S1 实机跑通：上屏、开面板、试听（`dumpsys media.audio_flinger` 有 1 条 active track）、番茄钟、返回；2026-11-14 又按本版重跑一遍上屏与截图（顶行「星期六 / 2026年11月14日 / 第 46 周」、倒计时 `⌛ 01:36:28`） |

## 音频外置（v24，2026-11-18）

音频不再内嵌在 `index.html`，而是同目录的 `rings/<n>.js`，按需加载：

| 文件 | 内容 |
| --- | --- |
| `page/rings/1.js` | `window.RING_DATA=window.RING_DATA||{};window.RING_DATA[0]="data:audio/wav;base64,…";` |

- 页面里 `RINGS` 只剩名字（`{n:'提示音', d:''}`）；`ringLoad(idx, cb)` 在首次用到该铃声时插入一个 `<script>`，把 `window.RING_DATA[idx]` 收进 `RINGS[idx].d`，再走原来的 `atob → decodeAudioData` 通道——**音频能力与内嵌版完全一致**，只是不再进首屏关键路径。
- 两个候选路径：同目录 `rings/<n>.js`（设备上是 `/system/etc/rings/`，模块挂载后可用），失败再找 `file:///sdcard/Android/data/<pkg>/files/rings/<n>.js`（App 自有外部目录，免存储权限）。
- 加载/解码失败时行为不变：`ringFail` → `alarmStart` 的 1.5 s 兜底蜂鸣，闹钟不会静默。
- 实测（TG_S1）：页面 5.5 MB→53 KB 后，`am force-stop` 到画面刷新的时间从 **32–38 s 降到 2.8–3.0 s**；试听时 `dumpsys media.audio_flinger` 的 track `Written` 从 84,224 涨到 150,784 帧，确认真在播。



- 顶行三段：左 `#dayLine`「星期六」`left:44px`、中 `#dateLine`「2026年11月14日」居中、右 `#weekLine`「第 46 周」`right:44px`，同为 26px `#8E8E8E`。**没有农历**：`LUNAR_INFO` 与 `solarToLunar` / `lunarText` 一整段已删。
- 倒计时行 `.cd-status` 在 `top:456px`：空闲 19px 极暗；运行时 30px `#EDEDED`、字距 3px、前缀 `⌛`（`U+231B`），底下垫 320×46 / `rgba(255,255,255,.08)` 圆角条（`::before`，`z-index:-1`）。
- 周数复用页面已有的 `isoWeek()`，与日历页「第 N 周」同口径；`tick()` 里只有值变了才写 DOM（`dayShown` / `weekShown` / `calKey` 三个守卫）。

## 硬约束（改之前先读）

1. **只许自制音频**：`page/index.html` 里不应再出现 `data:audio;base64`（判据：计数 0）；音频一律放 `page/rings/`，且只允许自制素材（`assets/chime.wav` 这类），不得提交第三方铃声。
2. **必须能在 Chrome 61 上活**：没有 flex `gap`、`transform` 要 `-webkit-` 前缀、`<audio>`/`new Audio()` 整条通道作废、多段 `<script>` 之间全局函数不可见（跨块要显式挂在 `window` 上）、长按 ~500ms 会被系统 contextmenu 抢事件。细节见 `../docs/PITFALLS.md` 的 B/C/D 三节。
3. **脚本块改完先做语法校验**（有 node 就行）：

   ```powershell
   $t=[IO.File]::ReadAllText('.\page\index.html')
   $m=[regex]::Match($t,'(?s)<script[^>]*>(.*?)</script>')
   $m.Groups[1].Value | Set-Content "$env:TEMP\blk.js" -Encoding utf8
   node --check "$env:TEMP\blk.js"
   ```
4. **探针、`window.onerror`、调试函数全部删净**：`lpDbg` 与 `window.onerror` 都应为 0 处（不要用 `Dbg` 这种宽词，会撞 base64 里的巧合子串）。

## 想要更多铃声（本地做，不要提交）

v24 起音频是独立文件，不再往页面里塞 base64。做法：把 `tools/pack_ringtones.py` 生成的 `data:audio/...;base64,…` 字符串按下面的形态写成 `page/rings/2.js`、`3.js`…（编号对应 `RINGS` 里的下标 +1），并在 `RINGS` 数组里补一行 `{n:'名字', d:''}`：

```js
window.RING_DATA=window.RING_DATA||{};window.RING_DATA[1]="data:audio/mpeg;base64,…";
```

`page/rings/` 里只放**你合法持有或自制**的音频；`page/index-local.html` 与本地铃声文件都被 `.gitignore` 的 `page/index-*.html` 规则挡在仓库外，不要 commit、不要随 Release 分发。

另外提醒一个已知脆弱点：`cdRing_v1` 存的是**数组索引**，所以 `RINGS` 的顺序一变，旧值就会指到别的铃声。改顺序时把浏览器里的 `cdRing_v1` 一起清掉。

## 部署

见 `../docs/DEPLOY.md` 第 8 节。一步到位就用 `../tools/deploy-page.ps1`——它走的是 **base64 经 adb stdin** 的通道，**不要用 `adb push`**：这台设备上 `adb push/pull/install` 会崩在 `file_sync_client.cpp:477 protocol fault`（见 `../docs/PITFALLS.md` E6）。
