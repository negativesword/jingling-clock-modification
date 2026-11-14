# 发布到 GitHub 的准备清单

这份清单解决三件事：**推什么、不推什么、怎么推**。按顺序做完即可发布。

---

## 0. 现在的状态：**已发布**

`https://github.com/negativesword/jingling-clock-modification`（public，main 分支，tag `v1.0.0` 指向首次发布；之后 `repo-2` / `repo-3` 两个补丁已随 `main` 推送，最新 commit 见仓库首页）

| 项 | 状态 | 位置 |
| --- | --- | --- |
| 页面本体 | ✅ 已就位，**已在实机跑通** | `page/index.html`（240,070 B / md5 `d25b6c44…`，1 段自制合成提示音） |
| 提示音源文件 | ✅ | `assets/chime.wav`（140,844 B，纯正弦合成，MIT 可分发） |
| 合成脚本 | ✅ | `tools/make_chime.py` |
| 截图 5 张 | ✅ 实机拍，已改名落盘 | `docs/images/`（main-clock / calendar / countdown-panel / pomodoro-focus / pomodoro-cfg） |
| 文档 6 篇 + 骨架 | ✅ | README / PUBLISH / docs×5（含 `SYSTEM-SLIMMING.md`）/ module / tools |
| **`git` 命令** | ✅ 已装（MinGit 便携版，`AppData\Local\git-mingit\cmd\git.exe`，v2.56.0） | 装法与踩点见第 4 节 |
| **本地仓库** | ✅ `git init -b main` + 提交完成，工作区干净 | `.git/` |
| **push 到 GitHub** | ✅ 已推上 `main`；`page/index.html` 推送后与本地逐字节一致（用 `git ls-tree` 的 blob sha 或 `Length` + MD5 对账即可） | 第 4 节 |
| **仓库简介 / Topics** | ✅ 已填（简介一句中文概述 + 10 个 topic：`android` `magisk` `webview` `kiosk` `flipclock` `pomodoro` `android-8` `mt8167s` `smart-display` `infoscreen`） | 仓库首页 About |
| **Release `v1.0.0`** | ✅ 已建，正文即第 4 节那份草稿的成品版 | Releases 页 |

### 页面是怎么从真机版变成仓库版的（可复现）

真机版（当年 v22b）= 5,517,842 B，其中七首 iOS 铃声的 base64 占了绝大部分；现在的真机版是 v23（5,515,727 B，同样带那七首铃声）。仓库版**用一段自制音频顶掉那七首**，而不是把 `RINGS` 置空——这样铃声行、试听按钮、`cdRing_v1` 这套逻辑在开源版里仍完整可见、可点、有声：

```bash
# ① 合成本仓库自己的提示音（988Hz + 1319Hz 叮咚，4.4s，16kHz/16bit/mono）
python tools/make_chime.py --wav assets/chime.wav

# ② 用同一条工具把它内嵌进页面，替换掉原来的 RINGS 数组
python tools/pack_ringtones.py --page page/index.html --src assets --names 提示音 --out page/index.html
```

结果：7 段 `data:audio/mpeg` → 1 段 `data:audio/wav`；体积 5,517,842 B → 242,233 B；`RINGS` 的 6 处引用全部保留；`node --check` 校验脚本块 `1 block / 219,467 chars / 0 失败`。

之后又把时钟页标语位置的公司名换成「×××」（11 个汉字 → 3 个字符，少 27 B），体积 → 242,206 B / md5 `c67bbded…`——这就是 `v1.0.0` 发布出去的那版。

**2026-11-14（`repo-3`）**：页面又跟了一批改动——删掉整套农历换算、顶行改三段式（左星期 / 中公历 / 右第几周）、倒计时运行态提亮到 30px 白字 + `⌛` + 8% 淡底条，体积降到 **240,070 B / md5 `d25b6c44…`**，`docs/images/main-clock.png` 也按这版在实机重拍（仍是匿名「×××」，不是后期涂改）。求证链路：本仓库这版页面推上设备 → `force-stop` → 18 秒后截图 → 确认顶行是「星期六 / 2026年11月14日 / 第 46 周」、倒计时行是 `⌛ 01:36:28`。

另外给番茄钟补了原来缺的那行兜底（`pmChime()` 里铃声失败就 `beepLoop()`，并在 6 秒收尾时清掉 `beepTimer`）——倒计时本来就有这条兜底，番茄钟当时没有。

### 为什么这一版能发

- 页面里**不含**任何第三方音频，唯一那段是我们自己算出来的正弦波（`assets/chime.wav` 与页面内嵌的是同一段）。
- 已在真机验证：上屏正常、面板能开、点「试听」后 `dumpsys media.audio_flinger` 出现 `1 Tracks of which 1 are active`（内嵌 WAV 解码 + WebAudio 播放真的响了）、番茄钟与设置页可进可退、返回后回主时钟页。

---

## 1. 仓库基本信息（可直接复制）

| 项 | 建议值 |
| --- | --- |
| 仓库名 | `tg-s1-infoscreen`（备选：`tmall-genie-tg-s1-clock`、`tg-s1-flipclock`） |
| 一句话简介 | 天猫精灵 TG_S1 / MT8167S / Android 8.1：不刷 GSI，用 Magisk systemless + WebView kiosk 改成常驻翻页钟 / 日历 / 倒计时 / 番茄钟信息屏 |
| Topics | `android` `magisk` `systemless` `kiosk` `webview` `flip-clock` `digital-clock` `calendar` `pomodoro` `mt8167s` `smart-speaker` `info-screen` |
| 主语言 | HTML（`page/`）+ Shell（`module/`） |
| License | MIT（仅覆盖本仓库代码与文档） |
| 默认分支 | `main` |
| Release | `v1.0.0` — "TG_S1 信息屏 v1：翻页钟 + 日历 + 倒计时 + 番茄钟" |

---

## 2. 推什么 / 不推什么

### ✅ 推

```
README.md
PUBLISH.md
LICENSE
.gitignore
docs/DEPLOY.md
docs/PITFALLS.md
docs/PAGE-SPEC.md
docs/VERSION_LOG.md
docs/SYSTEM-SLIMMING.md       ← 系统层瘦身：遮蔽清单、provider stub、suspend、回滚
docs/images/*.png            ← 5 张实机截图（README 已引用）
page/index.html              ← 页面本体（240,070 B，含 1 段自制合成提示音）
page/README.md
assets/chime.wav             ← 自制提示音源文件（.gitignore 里做了例外）
module/README.md
module/service.sh
tools/make_chime.py
tools/pack_ringtones.py
tools/deploy-page.ps1
```

### ❌ 不推（`.gitignore` 已挡）

| 内容 | 原因 |
| --- | --- |
| 七首 iOS 铃声（`RINGS` 里那 7 段 `data:audio/mpeg`） | 版权属 Apple，随页面分发属再分发；仓库版已替换掉 |
| `WebviewKiosk.apk` 及任何厂商/第三方 APK | 他人的作品，仓库只写"自行安装" |
| 分区镜像、`boot.img`、`nandroid` 备份 | 厂商版权 + 设备唯一标识 + 体积 |
| `/sdcard` 下的 dump 文本、leveldb 导出、调试日志 | 含设备路径、localStorage 内容 |
| `_backup/*.html` 各版本快照 | 含内嵌铃声；需要历史就看 `docs/VERSION_LOG.md` |

### 关于页面文件的三条硬要求（现状已全部满足）

1. **页面里只能有自制音频**。判据：`data:audio/mpeg;base64` 计数为 `0`、`data:audio/wav;base64` 计数为 `1`；体积 240,070 B 而不是 5.5 MB。
2. **即使一段音频都没有，到点也必须响**：`alarmStart()` 与 `pmChime()` 都在 1.5 秒内检查 `ringFail || !ringSrc`，命中就回落 `beepLoop()`（WebAudio 直接振荡，不依赖任何解码）。
3. **`assets/chime.wav` 不能被 `.gitignore` 的 `*.wav` 吃掉**——仓库里已经写了 `!assets/chime.wav` 例外，克隆下来用 `git check-ignore -v assets/chime.wav` 验证一下。

### 实名信息：页面与截图已匿名化

- 页面 `.caption` 与 `docs/images/main-clock.png` 上的公司名，发布版统一是「×××」；
- 提交作者的**邮箱**用的是 GitHub noreply 地址，真实邮箱不进历史；**提交者姓名仍保留真名**——这是仓库所有者自己的署名，若也要隐去，需 `git rebase --root --exec "git commit --amend --reset-author --no-edit"` 重写全部历史并 force-push，属于不可逆操作，本仓库没做；
- 截图只看得到时钟与面板，没有序列号、IP、通知栏；
- 设备侧真实名称只留在自用版 v23，不在仓库里出现；`LICENSE` 的版权行也改成 `tg-s1-infoscreen contributors`；
- 只改"最新版本"不够——旧 commit 里仍带着原名，因此发布时**把历史压成一个 commit 后 force-push，并把 `v1.0.0` 重新打到这个 commit 上**。验证方式：`git exec grep` 查原名应无命中，`git log --all` 只应剩这一个 commit。

---

## 3. 发布前最后一次自检

在 PC 的项目目录里执行（Windows PowerShell）：

```powershell
# ① 音频：mpeg 必须 0 条、wav 必须 1 条
(Select-String -Path .\page\index.html -Pattern 'data:audio/mpeg' -AllMatches -SimpleMatch | Measure-Object).Count   # 期望 0
(Select-String -Path .\page\index.html -Pattern 'data:audio/wav'  -AllMatches -SimpleMatch | Measure-Object).Count   # 期望 1

# ② 体积与指纹
Get-ChildItem .\page\index.html | Select-Object Name, Length
Get-FileHash .\page\index.html -Algorithm MD5        # 期望 d25b6c44645e4b1a0cba94be9a8615af

# ③ 有没有把本机绝对路径 / 私网 IP 带进文档
Select-String -Path .\README.md, .\docs\*.md, .\page\README.md, .\module\README.md -Pattern 'ZHU HONG|C:\\Users|192\.168\.' | Select-Object Path, LineNumber

# ④ 有没有残留调试代码（会撞到 base64 里的巧合子串，所以排除 Dbg 这个宽词）
$t=[IO.File]::ReadAllText('.\page\index.html')
"lpDbg: "        + ([regex]::Matches($t,'lpDbg')).Count          # 期望 0
"window.onerror: " + ([regex]::Matches($t,'window\.onerror')).Count  # 期望 0

# ⑤ 页面脚本块语法（有 node 就能跑，本次 0 失败）
$m=[regex]::Match($t,'(?s)<script[^>]*>(.*?)</script>')
$m.Groups[1].Value | Set-Content "$env:TEMP\blk.js" -Encoding utf8
node --check "$env:TEMP\blk.js"

# ⑥ 截图在不在
Get-ChildItem .\docs\images | Select-Object Name, Length
```

本项实测结果（数字为 2026-11-14 重跑）：

- ① `data:audio/mpeg` = **0**，`data:audio/wav` = **1**
- ② 240,070 B，MD5 = `D25B6C44645E4B1A0CBA94BE9A8615AF`（小写即 `d25b6c44…`）
- ③ 只有两处命中，都不是泄漏：`PUBLISH.md` 自己那行自检命令、`docs/DEPLOY.md` 里的 `192.168.x.x`（本来就脱敏成 x）
- ④ `lpDbg` = 0、`window.onerror` = 0；**不要用 `Dbg` 这个宽词去搜**，它会在 base64 里撞出假的命中
- ⑤ `node --check` 通过（1 个 script 块，217,726 chars）

---

## 4. 建仓与首次推送

### 这台机器上的 git 是怎么装上的

最初 `Get-Command git` 返回空，`winget` 虽然装了但不在 PATH 里，所以用了**免安装的 MinGit**（不需要管理员权限、不写注册表、不装 Git Bash）：

```powershell
# 1) 取 git-for-windows 最新 release 里的 MinGit 资产（约 40MB）
Invoke-WebRequest 'https://api.github.com/repos/git-for-windows/git/releases/latest' -UseBasicParsing |
  ConvertFrom-Json | % { $_.assets } | ? { $_.name -like 'MinGit*64-bit.zip' } | % { $_.browser_download_url }
# 2) 解压到用户目录，并把 cmd 目录加进用户级 PATH
Expand-Archive MinGit.zip 'C:\Users\<you>\AppData\Local\git-mingit' -Force
# 3) 验证
& 'C:\Users\<you>\AppData\Local\git-mingit\cmd\git.exe' --version   # git version 2.56.0.windows.4
```

> 想要完整版（带 Git Bash）：`winget install --id Git.Git -e --source winget`，或 `https://git-scm.com/download/win`。
>
> 一个反直觉的点：MinGit 名为"最小"，但 `ucrt64\bin\` 下**其实带了 `git-credential-manager.exe`**（还带 `git-credential-wincred.exe`）。所以在这台机器上 push 并没有弹任何登录——它直接读到了 Windows 凭据管理器里已有的 GitHub 登录态，一次就推上去了。判断办法是 `git push` 后看有没有让你输用户名；如果卡在 `could not read Username`，再补 PAT。

### 建仓时必须先关掉 CRLF 转换

Windows 上 git 默认 `core.autocrlf=true`，会在入库时把 LF 改成 CRLF。这套仓库里两样东西会被它直接搞坏：

- `module/service.sh` 变成 CRLF → Android 上 `sh` 解释器读不了（`bad interpreter` / 直接不执行）；
- `page/index.html` 字节数变化 → 文档里公示的 md5 `d25b6c44…` 当场失效，读者对不上账。

所以建仓第一步就写 `.gitattributes` 并设 `core.autocrlf=false`：

```powershell
@'
* text=auto eol=lf
*.png binary
*.wav binary
*.sh text eol=lf
'@ | Set-Content .gitattributes -Encoding ascii
git config core.autocrlf false
git config core.eol lf
```

验证办法：`git ls-tree -r -l HEAD` 里三个关键文件的 blob 体积必须与工作区一致——`page/index.html` 240,070 / `assets/chime.wav` 140,844 / `module/service.sh` 1,462。任何一个不等，就是行尾或过滤器动过手脚。

### 首次提交与推送（本机已执行完毕）

```bash
cd tg-s1-infoscreen
git init -b main
git add -A
git commit -m "feat: TG_S1 信息屏 v1 —— 翻页钟 / 日历 / 倒计时 / 番茄钟 + systemless 部署文档"

# 远端先建空仓库（不要勾 README / .gitignore / LICENSE，避免冲突）
git remote add origin https://github.com/negativesword/jingling-clock-modification.git
git push -u origin main
```

实际结果：远端原本是空仓库，push 输出 `* [new branch] main -> main`；本地 `HEAD` 与远端 `refs/heads/main` 都是 `e0eb584`，`page/index.html` 的 blob sha `2c398ff7…` 两边一致。

如果换一台机器、push 卡在 `could not read Username`，凭据三选一：

| 方式 | 做法 |
| --- | --- |
| PAT | GitHub → Settings → Developer settings → Personal access tokens 建 `repo` 权限的 token，push 时用户名填 GitHub 用户名、密码填 token |
| 完整版 git | 装 Git for Windows（带 Credential Manager），首次 push 弹浏览器登录 |
| 网页上传 | 不用 git：仓库页 "Add file → Upload files"，按目录把文件拖上去 |

提交身份用 GitHub 的 noreply 地址，避免真实邮箱进公开历史：

```bash
git config user.name  '<你的名字>'
git config user.email '46472575+negativesword@users.noreply.github.com'   # <GitHub 用户 id>+<用户名>
git commit --amend --reset-author --no-edit                                # 已有提交改署名
# 多个历史提交要一起改：git rebase --root --exec "git commit --amend --reset-author --no-edit"
```

下载加速（国内网络）：`https://ghfast.top/https://github.com/<owner>/<repo>/...`；查最新 release：`https://api.github.com/repos/<owner>/<repo>/releases/latest`。

打标签与 Release：

```bash
git tag -a v1.0.0 -m "v1.0.0"
git push origin v1.0.0
```

Release 说明草稿：

> **v1.0.0 — 信息屏可用版**
> - 翻页钟（时分秒三卡；顶行左星期 / 中公历 / 右第几周）；日历页左右滑切换
> - 倒计时：三列滚轮自定义时长、5 个可长按改写的快捷档、最后一分钟数秒、到点响铃（自带 beep 兜底）
> - 番茄钟：专注 / 短休 / 长休、轮次、自动接力、时长可调、断电续算
> - 部署文档：备份、Magisk systemless、kiosk 接管 HOME、精简、验收清单、按主题分组的踩坑清单
> - 不含任何商业铃声与第三方 APK；自带一段自制合成提示音，也可用 `tools/make_chime.py` 自己再造，或用 `tools/pack_ringtones.py` 内嵌自有音频

---

## 5. 图位（已就位）

`docs/images/` 里现在有 5 张，全部是实机截图（1024×600、无个人信息、无通知栏），README 已经按"读者最想看的顺序"引用：

| 文件名 | 内容 |
| --- | --- |
| `main-clock.png` | 时钟页成品（翻页钟 + 三段式顶行 + 标语位 ××× + 底部三图标 + 🍅 + ⌛ 倒计时行），2026-11-14 按 `repo-3` 页面重拍 |
| `calendar.png` | 日历页（左滑进入，红点标今天、第 46 周） |
| `countdown-panel.png` | 倒计时面板（三列滚轮 + 五个快捷格 + 铃声行「提示音」） |
| `pomodoro-focus.png` | 番茄钟专注态（`#BA4949` 红底、160px 大字、四颗轮次🍅） |
| `pomodoro-cfg.png` | 番茄钟设置页 |

README 已经用表格引用它们（两张一行，共三组）。还可以补一张 `architecture.png`——把 README 第 3 节的 ASCII 架构图重绘一遍；这不是必需项。

> 截图里不要出现设备序列号、私网 IP、通知栏个人信息。本仓库这 5 张是沉浸全屏直出，本身只有时钟/面板内容。

---

## 6. 发布后可以继续做的事

1. 把 `docs/PITFALLS.md` 单独发一篇 Issue 置顶（"这份踩坑清单欢迎补充"），比 README 更易被搜到。
2. 加 `CHANGELOG.md`，把 `docs/VERSION_LOG.md` 转成 Keep-a-Changelog 格式，v22b 作为首个条目。
3. 想要更小的页面：给 `tools/pack_ringtones.py` 加 `--only-selected` 参数，只内嵌当前选中那一首。
4. 想要别的机型复用：把 `docs/PAGE-SPEC.md` 里的 1024×600 常量抽成顶部 `:root` 变量，改一行即可适配。
