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
| 60s（先判重载） | 距上次拉起 ≥ 6 小时且设备本地时间在 03:00–04:59 → `am force-stop` + 重新拉起；若距上次 ≥ 30 小时（凌晨窗口连续错过）则不限时段立即重载 |

“定时重载”是为了对付 WebView 堆的长跑爬升：1 GB 内存装不下它一天后的工作集，活页被换进 zram，页面每秒刷新都要解压一次（major fault），内核态 CPU 被打满、整机变卡。重载期间页面空白约 30 秒（5.5 MB 母版），所以只放在凌晨窗口。启动时刻记在 `/data/local/tmp/kiosk_started`，是重载判定的基准；删掉它会当作“刚启动”，当天不再重载。阈值 `MIN_AGE_H` / `HARD_H` / `NIGHT_FROM` / `NIGHT_TO` 都在脚本头部，可改。

日志写 `/data/local/tmp/infoscreen.log`（可 `tail -f` 观察，长期运行注意体积，脚本里做了 200 行滚动的简易处理）。

> 这是按公开逻辑重写的参考实现，未在本文设备上逐行复核；上线前请先手工跑一遍：
> ```bash
> adb shell su -c "setsid sh /data/adb/modules/infoscreen/service.sh >/dev/null 2>&1 &"
> adb shell su -c "am force-stop uk.nktnet.webviewkiosk"
> adb shell su -c "tail -n 20 /data/local/tmp/infoscreen.log"     # 应看到 not running -> start
> ```

## 回滚

最快：在模块目录里 `touch disable`（Magisk 会跳过该模块但不卸载）。彻底：删目录 + 重启。
