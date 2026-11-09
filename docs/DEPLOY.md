# 部署手册

目标：把一台原厂状态的天猫精灵 CC（TG_S1）变成通电即亮的时钟/日历信息屏。
前提：你有这台设备的物理访问权，愿意承担刷机风险，并且**已经接受 `userdata` 没有备份**。

> 命令都在 Windows PowerShell + platform-tools 下执行，`adb` 指向 `192.168.x.x:5555`。
> 设备侧提权用 `su -c '<cmd>'`（Magisk）。

---

## 0. 先决条件

| 项 | 本机实测值 |
| --- | --- |
| 型号 | TG_S1（天猫精灵 CC） |
| SoC / 屏幕 | MT8167S，7 寸 1024×600 |
| 内存 | 1GB RAM + 512MB zram |
| 系统 | Android 8.1（sdk 27），纯 armeabi-v7a |
| WebView | `com.android.webview` 61.0.3163.98（Chrome 61） |
| adb | 网络 adb 常开（已刷 Magisk patch 过的 boot.img） |

**如果换一台设备，先跑这三条确认底子：**
```bash
adb shell getprop ro.build.version.sdk
adb shell dumpsys webviewupdate | grep -i "Current WebView package"
adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME
```
最后一条若返回**多个** HOME Activity，先读 `docs/PITFALLS.md` 的 A3，再往下做。

---

## 1. 备份（不做完不要往下走）

1. 备份全部分区（本机 21 个，共 1551.5 MB）。BROM 方式进 `mtkclient`，`printgpt` 拿分区表后逐区 dump。
2. **单独存一份原厂 boot.img 的 SHA1**，用来确认回滚成功（本机 `8a63db33…`，以你自己的为准）。
3. 记下当前 `package-restrictions.xml`、`user_settings.xml` 的原文件（base64 取回即可）。

> `userdata` / `cache` 不在备份范围。任何"恢复出厂才可撤销"的方案（如 Device Owner）都不要碰。

---

## 2. 装 Magisk（只动 boot）

1. 从原厂 boot.img 出发用 Magisk 打补丁，得到 `new-boot.img`。
2. `fastboot flash boot`（或 mtkclient 写回 boot 分区），首次开机会自动装 Magisk。
3. 验证：`adb shell su -c id` 返回 `uid=0`。

> 只改 boot，不碰 system/vendor——这是后面所有操作的前提（见 `PITFALLS.md` A1）。

---

## 3. 建 systemless 模块 `infoscreen`

模块目录结构（在 `/data/adb/modules/infoscreen/`）：

```
infoscreen/
├─ module.prop
├─ service.sh                     # 看门狗
└─ system/
   ├─ app/WebviewKiosk/WebviewKiosk.apk     # 第三方 kiosk 容器（自行安装，不入库）
   └─ etc/clock.html                        # 页面本体（bind mount 到 /system/etc/）
```

`module.prop` 最少要有：`id`、`name`、`version`、`versionCode`、`author`、`description`。
启用后重启一次，`ls -l /system/etc/clock.html` 与 `ls -l /system/app/WebviewKiosk/` 应能看到模块里的文件。

之后**改 clock.html 不需要再重启**——它是 bind mount 覆盖已有文件。

`service.sh`（看门狗，参考实现见 `module/service.sh`）：
- 每 20 秒判活：进程不在就 `am start -n uk.nktnet.webviewkiosk/.MainActivity`
- 每 60 秒判前台：当前 focused activity 不是 kiosk 就拉回前台
- 日志写 `/data/local/tmp/infoscreen.log`

临时测试不重启：
```bash
adb shell su -c "setsid sh /data/adb/modules/infoscreen/service.sh > /dev/null 2>&1 &"
```

---

## 4. 接管 HOME（组件级禁用）

1. 取回原文件：
```bash
adb shell su -c "base64 /data/system/users/0/package-restrictions.xml"
```
2. 本地解码 → 编辑 → `[xml]`（PowerShell）解析校验，确保没改坏。
3. 推回 + 修属性 + 软重启：
```bash
adb shell su -c "cp /sdcard/package-restrictions.xml /data/system/users/0/package-restrictions.xml"
adb shell su -c "chown system:system /data/system/users/0/package-restrictions.xml"
adb shell su -c "chmod 660 /data/system/users/0/package-restrictions.xml"
adb shell su -c "chcon u:o:system_data_file:s0 /data/system/users/0/package-restrictions.xml"
adb shell su -c "kill \$(pidof system_server)"
```
4. 验证只剩 kiosk：
```bash
adb shell su -c "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME"
```

**绝对不要**整包隐藏 `com.alibaba.ailabs.genie.smartapp`（见 A4）。

---

## 5. kiosk 设置

`uk.nktnet.webviewkiosk`（uid `u0_a24`）。它在 `shared_prefs/user_settings.xml` 里的关键项：

| 键 | 值 | 作用 |
| --- | --- | --- |
| `address_bar_mode` | `HIDDEN` | 隐藏地址栏 |
| `floating_toolbar_mode` | `HIDDEN` | 隐藏浮动工具条 |
| `immersive_mode` | `ALWAYS_ON` | 常驻沉浸全屏 |
| `keep_screen_on` | `true` | 常亮 |
| `refresh_on_screen_wake` | `true` | 亮屏刷新页面 |
| `lock_on_launch` | `true` | 启动即锁 |

首页 URL 必须是 `file:///system/etc/clock.html`，且**只能**用设置界面里 "Use the current URL" 那个按钮落盘（直接改 xml 不生效）。

路径：右下角扳手 `(944,528)` → 菜单 Home `(927,367)` / Lock `(927,416)` / Settings `(927,466)` → Settings 主页 Web Content `(512,100)` / Appearance `(512,411)` → Home URL 铅笔 `(987,97)` → 弹窗 `Use the current URL (512,290)` → `Save (744,416)`。

> kiosk 申请了但**没有授予** `READ/WRITE_EXTERNAL_STORAGE`，这是有意的：页面全部走 `file:///system/`，不需要外部存储。

---

## 6. 精简（debloat 模块）

新建 `/data/adb/modules/debloat/`，在 `system/app/<原目录名>/` 下放 **0 字节同名 apk** 占位覆盖。本机已压掉 13 个：

`AMPE`、`AliVideoPlayer`、`GenieAlbums`、`GenieBrowser`、`GenieIoT`、`GenieMonitor`、`GenieNetTest`、`GenieScreensaver`、`Osupdate`、`xiaoxiaoyouku`、`GenieLinkCamera`、`GenieAicare`、`HTMLOpen`

**必须保留**：天猫精灵语音四件套（唤醒 / ASR / TTS / NLU），以及 `com.alibaba.ailabs.genie.smartapp`。
**可删的临时物**：`/sdcard` 下的 dump 文本、截图；app 私有目录里的临时音频目录。

删之前先 `ls` 确认路径，逐个删、不要用通配批量删。

---

## 7. 验收清单

| # | 检查项 | 命令 / 动作 | 通过标准 |
| --- | --- | --- | --- |
| 1 | 冷启动进页面 | 拔电 ≥10s 再通电 | 30s 内出现时钟页 |
| 2 | HOME 归属 | `cmd package query-activities … HOME` | 只剩 kiosk + FallbackHome |
| 3 | 杀进程自恢复 | `am force-stop uk.nktnet.webviewkiosk` | ≤20s 自动回页面 |
| 4 | 页面三处一致 | `md5sum /system/etc/clock.html /sdcard/clock/index.html /data/adb/modules/infoscreen/system/etc/clock.html` | 三个 md5 相同 |
| 5 | 内存 | `cat /proc/meminfo` | MemAvailable 仍有 ~480MB |
| 6 | 出声 | 倒计时 1 分钟，到点后 `dumpsys media.audio_flinger` | `N Tracks of which 1 are active` |
| 7 | 断电续算 | 倒计时运行中拔电，重新上电 | 剩余时间按真实时间继续，不回到起点 |

---

## 8. 日常迭代（改页面）

```
1) 备份：cp page/index.html _backup/index-vNN-主题.html
2) 改本地 page/index.html（只改非 base64 段，见 PITFALLS E2）
3) 推送：tools/deploy-page.ps1 -LocalPath .\page\index.html -Device <device-ip>:5555
        → 先落 /data/local/tmp，md5 对账通过才 cp 到模块内 clock.html（立即生效）
        → 同时覆盖 /sdcard/clock/index.html 留底
4) 重载：su -c 'am force-stop uk.nktnet.webviewkiosk' + am start
5) 等首渲再 screencap：240KB 页面 8~10s；5.5MB 页面 32~38s（su 的 Toast 会遮画面，必要时补拍）
6) 逐项点测：把面板、按钮、长按、滑动都过一遍
```

**别用 `adb push`**：原型设备上 `adb push/pull/install` 一律崩在 `file_sync_client.cpp:477 protocol fault`。`deploy-page.ps1` 已经改走 base64 + adb stdin，并且**先写临时路径、对账通过才覆盖正式文件**——因为 `su -c 'nc ... > 正式文件'` 在设备连不上 PC 时会先把文件截成 0 字节，直接白屏（见 `docs/PITFALLS.md` E6）。

页面传得太慢或想省事时，还有一条 4 行的等价链路：

```powershell
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes('page/index.html'))
$b64 | & adb -s <device-ip>:5555 shell "su -c 'base64 -d > /data/local/tmp/new.html'"
& adb -s <device-ip>:5555 shell "su -c 'md5sum /data/local/tmp/new.html'"
& adb -s <device-ip>:5555 shell "su -c 'cp /data/local/tmp/new.html /data/adb/modules/infoscreen/system/etc/clock.html'"
```

页面状态乱了、想一键回到出厂默认（复位快捷格 / 番茄 / 铃声选择）：
```bash
adb shell su -c "am force-stop uk.nktnet.webviewkiosk"
adb shell su -c "rm -rf /data/data/uk.nktnet.webviewkiosk/app_webview/Local\ Storage"
adb shell su -c "am start -n uk.nktnet.webviewkiosk/.MainActivity"
```

读 localStorage（页面状态取证）：
```bash
adb shell su -c "ls -l '/data/data/uk.nktnet.webviewkiosk/app_webview/Local Storage/leveldb/'"
adb shell su -c "base64 '/data/data/uk.nktnet.webviewkiosk/app_webview/Local Storage/leveldb/000003.log'"
# 本地解码后用 ASCII 正则抓 pomo_s1.{0,150} / cdSlots_v1[\d,]{0,40} 等
```
文件名会滚动（`000003.log` → 别的编号），先 `ls`。

---

## 9. 出问题时

| 症状 | 先查什么 |
| --- | --- |
| 开机卡 logo | 是不是动过 system/vendor → 回滚 boot.img / 分区镜像 |
| 开机进原厂桌面 | HOME 组件禁用是否被写回；是不是冷启动后 match 值重算（见 A3） |
| 页面白屏 | `md5sum` 三处是否一致；是不是 0 字节（`md5` = `d41d8cd98f00b204e9800998ecf8427e` 就是空文件，多半是 `nc > 文件` 或推送中断）；**恢复只需 `su -c 'cp /sdcard/clock/index.html <模块路径>'`**（E6） |
| 按钮点不动 | 先查 `window.onerror` 探针，多半是初始化抛异常（B1） |
| 面板关不掉 / 关掉又弹另一个 | C5 的穿透问题 |
| 到点不出声 | `dumpsys audio` 是否静音；`audioWake()` 是否在手势里调用；用 `dumpsys media.audio_flinger` 看有没有 `Tracks of which 1 are active` |
| 反复重启 | `dmesg | grep AEE`，看是不是某个已删包引发 `SecurityException` 计数 |
| `adb push` 报 `protocol fault` | 这是本机常态，不是偶发；改用 base64 + adb stdin（E6） |

**回滚手段**：Magisk 里禁用/删除模块 → 重启；或恢复 boot.img + 恢复 `package-restrictions.xml` 备份。
