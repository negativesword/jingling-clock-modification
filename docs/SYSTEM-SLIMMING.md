# 系统层瘦身：把三个原厂包从系统里「摘掉」

这台机器只有 1GB 内存、4 核，原厂固件里塞了一整套天猫精灵语音栈。信息屏只要求「点亮一块表」，所以本章做的事是：**在不碰只读分区的前提下，让用不上的系统包从包管理器里彻底消失**，再把因此缺失的 provider 用自建 APK 补上。

> 所有操作都在 `Magisk 27.0` 的 systemless 层完成：卸载模块或删掉占位文件，重启即回到出厂状态。

---

## 1. 收益（本机实测）

| 项 | 遮蔽前 | 遮蔽后 |
| --- | --- | --- |
| 开机 50 分钟的 `MemAvailable` | 496 MB | **593 MB** |
| CPU 可用核数 | 语音栈常驻时相当于少一整核 | 4 核全部归信息屏 |
| `com.alibaba.ailabs.genie.smartapp` 常驻 RSS | 约 90 MB | 包不存在 |
| HOME 键 | 原厂桌面 | 只剩 kiosk |

另有 10 个精灵系/输入法包处于 `suspend` 状态、NTP 换成阿里云，见第 5、6 节。

---

## 2. 手段一：0 字节占位（systemless 遮蔽）

Magisk 的 systemless 覆盖可以「遮蔽」系统文件：在模块目录里放一个同名文件，Magisk 会把真实的 `/system/app/<pkg>/<pkg>.apk` 藏起来，让包扫描看不到它。

```bash
# 模块内目录结构（debloat 模块）
/data/adb/modules/debloat/system/app/smartapp/smartapp.apk          # 0 字节，644
/data/adb/modules/debloat/system/app/AliGenieService/AliGenieService.apk
/data/adb/modules/debloat/system/app/GenieRTC/GenieRTC.apk
...
```

本机现役 16 个占位：

| 类别 | 包 |
| --- | --- |
| 语音栈（本轮新增 3 个） | `smartapp`、`AliGenieService`、`GenieRTC` |
| 精灵系外围 | `GenieIoT`、`GenieMonitor`、`GenieAicare`、`GenieAlbums`、`GenieScreensaver`、`GenieLinkCamera`、`GenieBrowser`、`GenieNetTest`、`AMPE`、`xiaoxiaoyouku` |
| 媒体/OTA/HTML | `AliVideoPlayer`、`Osupdate`、`HTMLOpen` |

**必须保留**：语音四件套（唤醒 / ASR / TTS / NLU）。它们不是这次瘦身的对象，遮蔽后设备连"小精灵"都叫不动，且没有可测的收益。

> 占位文件必须是 **0 字节、权限 644**。塞一个真 APK 进去不是遮蔽，是替换。

---

## 3. 手段二：provider stub（不做这步就得把 smartapp 放回来）

### 现象

只遮蔽 `smartapp`、`AliGenieService`、`GenieRTC` 三包、重启后：

- 三包确实从 `cmd package list packages` 里消失，内存与 CPU 都省下来了；
- 但 `SystemUI` 开始**周期性崩溃**，且崩溃间隔逐次拉长（1 分钟 → 2 分钟 → 4 分钟 → …，标准的崩溃-退避链），最后被 MTK AEE 计数到阈值，整机重启。

### 根因

`SettingsProvider`、`SystemUI` 等系统进程会 `query` 一批由天猫精灵提供的 `ContentProvider`。包被遮蔽后这些 authority 无人声明，`query` 抛 `SecurityException` / 返回 null，调用方没做判空 → SystemUI 崩 → 退避 → 再崩。

涉及 6 个 authority：

```
com.alibaba.ailabs.genie.datacenter.DataCenterProvider
com.alibaba.ailabs.childmode.provider
com.alibaba.ailabs.genie.assistant.server
com.alibaba.ailabs.genie.router.ipc.service
com.alibaba.ailabs.genie.assistant.provider
com.alibaba.ailabs.telecom.bind.provider
```

### 解法：一个 8.6 KB 的桩 APK

自建 `com.zhu.geniestub`，只做一件事：**声明上述 6 个 authority，所有 `query` 返回非 null 的空游标**。

```java
// 全部查询返回空 MatrixCursor，列名给一个通用 value
private Cursor emptyCursor() { return new MatrixCursor(new String[]{"value"}); }
@Override public Cursor query(Uri uri, String[] projection, ...) { return emptyCursor(); }
```

- 产物：`GenieStub.apk`（8,595 B，`minSdk 27 / targetSdk 27`，`android:exported="true"`、`multiprocess=false`）
- 装机后常驻 RSS 约 20 MB；`pidof com.zhu.geniestub` 有值即生效
- 该 APK **不进本仓库**（含自签名密钥），构建脚本见第 4 节

### 残留（如实记录）

stub 返回的是**空游标**，调用方按列取不到数据、也拿不到 `getExtras().getBinder()`，于是仍会打印：

```
W System.err: java.lang.NullPointerException: Attempt to invoke virtual method
'android.os.IBinder com.alibaba.ailabs.ipc.bean.BinderWrapper.getBinder()' on a null object reference
```

这些是**被调用方自己 catch 住的告警**，不进崩溃链：本机重启后 `SystemUI` pid 851 从开机起未再重启。它们只在有进程来查时才出现（实测集中在开机后与偶发的设置查询，不是每分钟定时触发）。要彻底消掉只能把 `smartapp` 放回来，得不偿失。

---

## 4. 重建 stub（需要另一台机器）

工程依赖（约 500 MB，不入库）：

| 组件 | 版本 |
| --- | --- |
| JDK（编译） | 11.0.2（`sdkmanager` 需要 17） |
| build-tools | 32.0.0 |
| platform | android-27 |

构建步骤（`build.ps1`，本机脚本只调 jar、绕开会在 JDK 9+ 崩的 `.bat`）：

1. `aapt2 link` 生成未签名 APK（只带清单，无资源）
2. `javac` 编译 `StubDataCenterProvider.java`（`-source 8 -target 8`）
3. `java -cp lib\d8.jar com.android.tools.r8.D8 --min-api 27` 产出 `classes.dex`
4. 用 `ZipArchive` 把 `classes.dex` 塞进 APK
5. `zipalign -f 4`
6. `keytool` 生成本地密钥（仅首次）
7. `java -cp lib\apksigner.jar com.android.apksigner.ApkSignerTool sign`，再 `verify`

安装（`install.ps1`）：这台机器的 `adb install` 会崩在 `file_sync_client.cpp:477`，`pm install` 又是 `unknown command`，所以走**安装会话 + stdin**：

```bash
# APK 先用 base64 落到 /data/adb/tmp/GenieStub.apk
S=$(cmd package install-create -r -t -S <size> | sed 's/.*\[//;s/\].*//')
cat /data/adb/tmp/GenieStub.apk | cmd package install-write -S <size> $S base -
cmd package install-commit $S
```

装完逐个自查 authority 是否已被认领：

```bash
content query --uri content://com.alibaba.ailabs.genie.datacenter.DataCenterProvider
# 只要不再报 "Failed to find provider" 即成功；stub 返回空结果属正常
```

---

## 5. 手段三：suspend

`cmd package suspend` 让包保留、但不允许其活动与后台进程运行。本机原计划 13 个，实际现状：

| 状态 | 数量 | 说明 |
| --- | --- | --- |
| `suspended=true` | 10 | `game.center`、`genie.cook`、`genie.camera`、`genie.children`、`genie.guide`、`genie.waft`、`genie.aihuman`、`ktcp.aiagent`、`yunos.tv.alitvasr`、`inputmethod.pinyin` |
| 已从包管理器消失 | 3 | `aligenie.ags`、`alibaba.genie.rtc`、`genie.smartapp` —— 被遮蔽了，`dumpsys` 里已无此包，suspend 自然失效 |

注意两点：

- **suspend 状态会持久化**，重启后 `suspended=true` 仍在，不需要每次重新执行。
- **suspend 挡不住系统主动拉起。** `com.google.android.inputmethod.pinyin` 虽被 suspend，但作为系统里唯一注册的输入法，开机仍被 `InputMethodManager` 拉起，常驻约 70 MB。想省这 70 MB 只能换一个输入法或让系统无 IME——本机没做，属于已知遗留。

---

## 6. 手段四：NTP 换阿里云

原厂默认走境外池，一次校时实测 255 ms。改成阿里云：

```bash
su -c 'settings put global ntp_server ntp.aliyun.com'
```

写进 `global` 设置项，下一次 NTP 轮询即生效，不需要重启。回滚：

```bash
su -c 'settings put global ntp_server 2.android.pool.ntp.org'
```

---

## 7. 完整回滚

```bash
# ① 撤销遮蔽：删掉占位即可，重启后原包回来
su -c 'rm -rf /data/adb/modules/debloat'

# ② 撤销 stub（可选：遮蔽没了就该删，避免它抢占 authority）
su -c 'pm uninstall com.zhu.geniestub'

# ③ 撤销 suspend
su -c 'cmd package unsuspend --user 0 <pkg>'

# ④ NTP 回默认
su -c 'settings put global ntp_server 2.android.pool.ntp.org'
```

做完重启一次。`infoscreen` 模块与页面不受影响。

---

## 8. 已验证走不通的做法（别再试）

| 做法 | 结果 |
| --- | --- |
| 直接把 `smartapp` 整包 `uninstall` / `pm hide` | 本机 `pm` 无 disable/hide 命令；即便成功也会走上面那条 SystemUI 崩溃-退避链 |
| 遮蔽后「恢复 smartapp + `renice 19` 降权 + 塞进 background cpuset」 | 能让系统不崩，但 90 MB 常驻与忙循环都回来了；只在没有 stub 时的折中方案，本轮选了 stub |
| 直接改 `/system` 删包 | dm-verity 下改一个字节就 EIO 卡 logo 无限重启 |
| 用 `busybox`/`sqlite3` 手改 `package-restrictions.xml` 整包禁用 | 组件级禁用只对 HOME Activity 有效；整包级还是回到 provider 缺失 |

---

## 9. 验收清单

```bash
# 遮蔽是否生效（三包应无输出）
su -c 'cmd package list packages | grep -E "genie.smartapp|aligenie.ags|alibaba.genie.rtc"'

# stub 是否在跑
pidof com.zhu.geniestub

# SystemUI 是否稳定（隔几分钟看两次，pid 应不变）
pidof com.android.systemui

# 资源现状
su -c 'cat /proc/meminfo | grep -E "MemTotal|MemAvailable|SwapFree"'
su -c 'ps -A -o PID,RSS,NAME --sort=-rss | head -8'

# 最近有没有把系统搞崩的痕迹
su -c 'ls -lt /data/system/dropbox/ | head -5'
```
