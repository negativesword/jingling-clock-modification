# module/

Magisk systemless 模块 `infoscreen` 的结构说明。仓库里只放**可以公开的实现**（`service.sh` + 本说明），不放 APK、不放固件。

## 目录结构（设备侧）

```
/data/adb/modules/infoscreen/
├─ module.prop
├─ service.sh
├─ disable            ← 可选：存在即禁用模块（回滚最快的方式）
└─ system/
   ├─ app/WebviewKiosk/WebviewKiosk.apk
   └─ etc/clock.html
```

`module.prop` 最少字段：

```properties
id=infoscreen
name=TG_S1 Info Screen
version=v1.0.0
versionCode=1
author=<your-name>
description=常驻时钟/日历信息屏：bind mount clock.html，配看门狗自动拉起 WebView kiosk
```

## 为什么走 systemless

- 设备 system/vendor 有 dm-verity，改一个字节就 EIO 卡 logo。systemless 只 patch boot，模块随时可 disable。
- `clock.html` 是**覆盖已有文件**，所以改页面是 bind mount 立即生效，**不需要重启**。
- 模块里**新增**文件不会热挂载（例如新放一首铃声到 `system/etc/ringtones/`），必须等重启——这也是最终放弃"外部音频文件"路线的原因之一（见 `docs/PITFALLS.md` D1）。

## service.sh

`service.sh` 是 Magisk 的开机服务脚本，参考实现见同目录文件。逻辑：

| 周期 | 动作 |
| --- | --- |
| 20s | `pidof uk.nktnet.webviewkiosk` 为空 → `am start -n uk.nktnet.webviewkiosk/.MainActivity` |
| 60s | 判当前 resumed activity 是否 kiosk；不是就拉回前台 |
| 60s（先判重载） | 距上次拉起 ≥ 4 小时，且本地时间落在两个触发点之一 → `am force-stop` + 重新拉起：① 22:00–22:19 ② 07:40–07:59。**08:00–22:00 一律不重载**；超过 26 小时未重载时，只在允许窗口（22:00–08:00）内补一次 |

“定时重载”是为了对付 WebView 堆的长跑爬升：`meminfo` 采样证明它按 21–24 MB/h 单调上涨、没有平台期，1 GB 内存装不下一天后的工作集，活页被换进 zram，页面每秒刷新都要解压一次（major fault），内核态 CPU 被打满、整机变卡。v24 页面只有 53 KB，重载白屏实测 2.8–3.0 秒，所以一天重载两次（22:00 与 07:40），并明确避开 08:00–22:00 的使用时段。启动时刻记在 `/data/local/tmp/kiosk_started`，是重载判定的基准。阈值 `MIN_AGE_H` / `HARD_H` / `EVEN_H` / `EVEN_WIN` / `MORN_H` / `MORN_FROM` 都在脚本头部，可改。`sh service.sh --test-due <epoch>` 可以在不改动现场的前提下打印某时刻的判定结果（0=该重载 / 1=不重载）。

日志写 `/data/local/tmp/infoscreen.log`（可 `tail -f` 观察，长期运行注意体积，脚本里做了 200 行滚动的简易处理）。

> 这是按公开逻辑重写的参考实现，未在本文设备上逐行复核；上线前请先手工跑一遍：
> ```bash
> adb shell su -c "setsid sh /data/adb/modules/infoscreen/service.sh >/dev/null 2>&1 &"
> adb shell su -c "am force-stop uk.nktnet.webviewkiosk"
> adb shell su -c "tail -n 20 /data/local/tmp/infoscreen.log"     # 应看到 not running -> start
> ```

## 回滚

最快：在模块目录里 `touch disable`（Magisk 会跳过该模块但不卸载）。彻底：删目录 + 重启。
