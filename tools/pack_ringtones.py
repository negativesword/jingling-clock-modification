#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pack_ringtones.py — 把你自己合法持有的音频内嵌进单文件页面（重写 RINGS 数组）。

用途：仓库里的 page/index.html 刻意不带铃声（商业铃声不可再分发）。
      在自己设备上想用某几首时，本地跑一遍这个脚本生成一份"只给自己用"的页面。

用法：
  python tools/pack_ringtones.py --page page/index.html --src "D:/my-ringtones" --out page/index-local.html
  python tools/pack_ringtones.py --page page/index.html --check      # 只看现状，不改文件

参数：
  --page    源页面（含 RINGS = [ ... ]; 这一段）
  --src     音频目录，按文件名排序取；支持 .mp3 .ogg .m4a .wav
  --out     输出页面，默认 page/index-local.html
  --names   界面显示名，逗号分隔；数量不足时用文件名
  --check   只报告当前内嵌了几段音频，不做修改

注意：
  内嵌后页面体积会明显变大（一首 1MB 的 mp3 编成 base64 约 1.4MB）。
  老 WebView 解码是纯软件路径，单首建议 ≤ 1.5MB、总时长 ≤ 12s，否则首次解码会明显卡顿。
"""

import argparse
import base64
import io
import os
import re
import sys

AUDIO_EXT = {".mp3": "audio/mpeg", ".ogg": "audio/ogg", ".m4a": "audio/mp4", ".wav": "audio/wav"}
MIME_DEFAULT = "audio/mpeg"


def find_array(text):
    """定位 RINGS = [ ... ]; 并返回 (start, end, body)。end 指 ']' 之后（含可选的 ';'）。"""
    m = re.search(r"RINGS\s*=\s*\[", text)
    if not m:
        raise SystemExit("未找到 RINGS = [ ... ] 段，请确认这是本项目的页面文件。")
    start = m.start()
    lb = text.index("[", m.start())
    depth = 0
    i = lb
    in_str = None
    while i < len(text):
        ch = text[i]
        if in_str:
            if ch == "\\":
                i += 2
                continue
            if ch == in_str:
                in_str = None
        elif ch in ("'", '"'):
            in_str = ch
        elif ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                end = i + 1
                if end < len(text) and text[end] == ";":
                    end += 1
                return start, end, text[lb + 1:i]
        i += 1
    raise SystemExit("RINGS 数组没有闭合，页面文件可能被截断。")


def collect(src, names):
    files = []
    for name in sorted(os.listdir(src)):
        ext = os.path.splitext(name)[1].lower()
        if ext in AUDIO_EXT:
            files.append(os.path.join(src, name))
    if not files:
        raise SystemExit("目录里没有可用的音频文件：%s" % src)
    out = []
    for idx, path in enumerate(files):
        mime = AUDIO_EXT[os.path.splitext(path)[1].lower()]
        raw = open(path, "rb").read()
        label = names[idx] if idx < len(names) else os.path.splitext(os.path.basename(path))[0]
        out.append((label, mime, raw))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--page", required=True)
    ap.add_argument("--src")
    ap.add_argument("--out")
    ap.add_argument("--names", default="")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()

    text = io.open(a.page, encoding="utf-8").read()

    if a.check:
        n = text.count("data:audio/")
        print("内嵌音频段数：%d" % n)
        print("文件体积：%d B" % len(text.encode("utf-8")))
        if n:
            print("⚠ 该页面含内嵌音频，不要提交到公开仓库。")
        return

    if not a.src:
        raise SystemExit("需要 --src 指定音频目录（或用 --check 只看现状）")
    names = [s.strip() for s in a.names.split(",") if s.strip()] if a.names else []
    items = collect(a.src, names)

    total = 0
    lines = []
    for label, mime, raw in items:
        b64 = base64.b64encode(raw).decode("ascii")
        total += len(b64)
        lines.append("  {n:'%s', d:'data:%s;base64,%s'}" % (label.replace("'", ""), mime, b64))
    arr = "RINGS = [\n" + ",\n".join(lines) + "\n];"

    start, end, _ = find_array(text)
    new_text = text[:start] + arr + text[end:]

    out = a.out or os.path.join(os.path.dirname(a.page), "index-local.html")
    io.open(out, "w", encoding="utf-8", newline="\n").write(new_text)

    print("写入 %s" % out)
    for label, mime, raw in items:
        print("  %-10s %-12s %8d B  -> base64 %8d B" % (label, mime.split("/")[-1], len(raw), len(base64.b64encode(raw))))
    print("页面体积 %d -> %d B" % (len(text.encode("utf-8")), len(new_text.encode("utf-8"))))
    print("base64 合计约 %d B（页面会因此变重，注意首渲时间）" % total)
    print("\n提醒：输出文件只给自己设备用，不要 commit、不要随 Release 分发。")


if __name__ == "__main__":
    main()
