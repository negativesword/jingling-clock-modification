# page/

`index.html` 就是页面本体：单文件、自包含、能在 Chrome 61（Android 8.1 WebView）上跑。把它推到设备上就是整块信息屏的全部 UI。

## 这一版里有什么

| 项 | 值 |
| --- | --- |
| 体积 | 240,070 B（代码约 40KB + 一段自制合成提示音 base64 187,792 B） |
| MD5 | `d25b6c44645e4b1a0cba94be9a8615af` |
| 音频 | 只有 1 段：`data:audio/wav;base64,…`，来自 `../assets/chime.wav` |
| 商业素材 | 无（七首 iOS 铃声已全部剔除） |
| 已验证 | 2026-11-09 推上 TG_S1 实机跑通：上屏、开面板、试听（`dumpsys media.audio_flinger` 有 1 条 active track）、番茄钟、返回；2026-11-14 又按本版重跑一遍上屏与截图（顶行「星期六 / 2026年11月14日 / 第 46 周」、倒计时 `⌛ 01:36:28`） |

## 当前界面（v23）

- 顶行三段：左 `#dayLine`「星期六」`left:44px`、中 `#dateLine`「2026年11月14日」居中、右 `#weekLine`「第 46 周」`right:44px`，同为 26px `#8E8E8E`。**没有农历**：`LUNAR_INFO` 与 `solarToLunar` / `lunarText` 一整段已删。
- 倒计时行 `.cd-status` 在 `top:456px`：空闲 19px 极暗；运行时 30px `#EDEDED`、字距 3px、前缀 `⌛`（`U+231B`），底下垫 320×46 / `rgba(255,255,255,.08)` 圆角条（`::before`，`z-index:-1`）。
- 周数复用页面已有的 `isoWeek()`，与日历页「第 N 周」同口径；`tick()` 里只有值变了才写 DOM（`dayShown` / `weekShown` / `calKey` 三个守卫）。

## 硬约束（改之前先读）

1. **只许自制音频**：文件里不应该再出现 `data:audio/mpeg;base64`。判据：`data:audio/mpeg` 计数 0、`data:audio/wav` 计数 1。
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

```bash
# ① 先造/找一段你自己合法持有的音频（或直接改 tools/make_chime.py 的频率与节奏再造一段）
python tools/make_chime.py --wav assets/chime.wav          # 仓库自带的合成提示音就是这么来的

# ② 内嵌进一个本地副本，不要覆盖仓库里的 index.html
python tools/pack_ringtones.py --page page/index.html --src "D:/my-ringtones" --out page/index-local.html
```

`page/index-local.html` 会被 `.gitignore` 里的 `page/index-*.html` 规则挡在仓库外。生成物里有 `data:audio/...;base64,` 的内嵌音频，**只给自家设备用，不要 commit、不要随 Release 分发**。

另外提醒一个已知脆弱点：`cdRing_v1` 存的是**数组索引**，所以 `RINGS` 的顺序一变，旧值就会指到别的铃声。改顺序时把浏览器里的 `cdRing_v1` 一起清掉。

## 部署

见 `../docs/DEPLOY.md` 第 8 节。一步到位就用 `../tools/deploy-page.ps1`——它走的是 **base64 经 adb stdin** 的通道，**不要用 `adb push`**：这台设备上 `adb push/pull/install` 会崩在 `file_sync_client.cpp:477 protocol fault`（见 `../docs/PITFALLS.md` E6）。
