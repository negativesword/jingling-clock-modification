# deploy-page.ps1 — 推页面 → 对账 → 重载 kiosk → 截图
#
# 用法：
#   .\tools\deploy-page.ps1 -LocalPath .\page\index.html -Device 192.168.2.125:5555
#   .\tools\deploy-page.ps1 -LocalPath .\page\index-local.html -WaitSec 40
#
# 为什么不用 adb push：
#   本方案的原型设备上 `adb push/pull/install` 一律崩在
#   `F adb.exe: file_sync_client.cpp:477 protocol fault: failed to read stat response`，
#   连 240KB 的文件都会崩。这里改走 **base64 + adb shell 的 stdin**：
#   不依赖 PC 的 IP、不用开端口、不经过 adb 的文件同步通道。
#
# 流程（与 docs/DEPLOY.md 第 8 节一致）：
#   1. 本地 md5 / 体积
#   2. base64 经 adb shell stdin 落到 /data/local/tmp/（绝不直接写正式文件）
#   3. 设备端 md5sum 对账，不一致直接中止
#   4. 对账通过才 cp 到模块内的 clock.html（bind mount，立即生效）
#   5. 同步一份到 /sdcard/clock/index.html 留底（出事时可就地恢复）
#   6. force-stop kiosk → 等 WaitSec 秒 → base64 取屏落 PNG
#
# 注意：绝不要用 `su -c 'nc ... > 正式文件'` 这种写法。设备没连上 PC 时，shell 重定向会
#      在连接建立之前就把目标文件截成 0 字节，页面直接空白屏（见 docs/PITFALLS.md E6）。

param(
  [Parameter(Mandatory = $true)][string]$LocalPath,
  [string]$Adb = "adb",
  [string]$Device = "192.168.2.125:5555",
  [string]$RemoteModule = "/data/adb/modules/infoscreen/system/etc/clock.html",
  [string]$RemoteBackup = "/sdcard/clock/index.html",
  [string]$RemoteTmp = "/data/local/tmp/clock-deploy.html",
  [int]$WaitSec = 10
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $LocalPath)) { throw "本地文件不存在：$LocalPath" }

$localMd5 = (Get-FileHash -LiteralPath $LocalPath -Algorithm MD5).Hash.ToLower()
$size = (Get-Item -LiteralPath $LocalPath).Length
Write-Host ("本地 : {0}  {1} B  md5 {2}" -f $LocalPath, $size, $localMd5)

# 0) 设备在线检查
$state = (& $Adb -s $Device get-state 2>&1) -join ""
if ($state -notmatch "device") { throw "设备不在线：$Device（先 adb connect $Device）" }

# 1) base64 经 stdin 落到临时路径
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $LocalPath).Path))
$b64 | & $Adb -s $Device shell "su -c 'base64 -d > $RemoteTmp'"
if ($LASTEXITCODE -ne 0) { throw "stdin 传输失败（exit $LASTEXITCODE）" }

# 2) 对账
$remote = (& $Adb -s $Device shell "su -c 'md5sum $RemoteTmp; wc -c $RemoteTmp'" 2>&1) -join " "
$remoteMd5 = ($remote -split "\s+")[0].Trim().ToLower()
if ($remoteMd5 -ne $localMd5) {
  throw ("远端 md5 不一致：本地 {0} / 设备 {1}（{2}）。文件可能被截断，未覆盖正式页面。" -f $localMd5, $remoteMd5, $remote.Trim())
}
Write-Host ("远端 md5 一致：{0}" -f $remoteMd5)

# 3) 覆盖正式页面 + 留底
& $Adb -s $Device shell "su -c 'cp $RemoteTmp $RemoteModule; cp $RemoteTmp $RemoteBackup'" | Out-Null
$after = ((& $Adb -s $Device shell "su -c 'md5sum $RemoteModule $RemoteBackup'" 2>&1) -join " ")
Write-Host ("生效路径 md5：" + $after.Trim())

# 4) 重载
& $Adb -s $Device shell "su -c 'am force-stop uk.nktnet.webviewkiosk'" | Out-Null
& $Adb -s $Device shell "am start -n uk.nktnet.webviewkiosk/.MainActivity" | Out-Null
Write-Host ("已重载，等待 {0}s 让页面首渲完成…" -f $WaitSec)
Start-Sleep -Seconds $WaitSec

# 5) 截图（base64 取回，避免 adb pull）
$b64 = (& $Adb -s $Device shell "screencap -p | base64") -join "" -replace "\s", ""
$png = (Resolve-Path -LiteralPath $LocalPath).Path -replace "\.html$", ".shot.png"
[IO.File]::WriteAllBytes($png, [Convert]::FromBase64String($b64))
Write-Host ("截图：{0}" -f $png)
