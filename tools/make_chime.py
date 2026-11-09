#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_chime.py — 生成一段自制提示音（版权干净），供 page/index.html 内嵌。

仓库不包含任何商业铃声（iOS 系统铃声版权属 Apple，不可再分发）。
本脚本用纯数学合成一段"叮咚"提示音，输出 16kHz/16bit/mono WAV：

  python tools/make_chime.py --wav assets/chime.wav
  python tools/pack_ringtones.py --page page/index.html --src assets --names 提示音 --out page/index.html

生成的音频为纯合成波形，随仓库以 MIT 发布，可自由使用。
"""

import argparse
import array
import math
import wave

SR = 16000          # 采样率：够用且体积小（老 WebView 解码压力低）
DUR = 4.4           # 总时长（秒），与播放循环周期一致
CYCLE = 1.1         # 单次"叮咚"周期
TONE_A = 988.0      # 第一声（B5 附近，明亮）
TONE_B = 1319.0     # 第二声（E6），比第一声高，形成上扬
A_DUR = 0.25        # 第一声时长
B_DUR = 0.40        # 第二声时长
B_OFFSET = 0.22     # 第二声相对第一声的起点
GAIN = 0.55


def tone(freq, dur, decay=6.0):
    """正弦 + 指数衰减包络；带 8ms 淡入避免爆音。"""
    n = int(SR * dur)
    fade = int(SR * 0.008)
    out = []
    for i in range(n):
        t = i / SR
        env = math.exp(-decay * t)
        if i < fade:
            env *= i / fade
        out.append(math.sin(2 * math.pi * freq * t) * env)
    return out


def build():
    total = int(SR * DUR)
    acc = [0.0] * total
    a = tone(TONE_A, A_DUR)
    b = tone(TONE_B, B_DUR, decay=5.0)

    cycle = 0
    while True:
        base = int(SR * CYCLE * cycle)
        for i, v in enumerate(a):
            idx = base + i
            if idx < total:
                acc[idx] += v * 0.9
        off = base + int(SR * B_OFFSET)
        for i, v in enumerate(b):
            idx = off + i
            if idx < total:
                acc[idx] += v
        cycle += 1
        if base >= total:
            break

    # 归一化 + 转 16bit，并做首尾交叉淡出，循环播放时不"咔"
    peak = max(1e-9, max(abs(x) for x in acc))
    scale = (32767 * GAIN) / peak
    pcm = array.array("h", [int(max(-32768, min(32767, x * scale))) for x in acc])
    tail = int(SR * 0.05)
    for i in range(tail):
        pcm[i] = int(pcm[i] * (i / tail))
        pcm[-1 - i] = int(pcm[-1 - i] * (i / tail))
    return pcm


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wav", default="assets/chime.wav")
    a = ap.parse_args()
    pcm = build()
    import os
    os.makedirs(os.path.dirname(a.wav) or ".", exist_ok=True)
    with wave.open(a.wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("写入 %s  %d 帧  %.2fs  %d B" % (a.wav, len(pcm), len(pcm) / SR, os.path.getsize(a.wav)))


if __name__ == "__main__":
    main()
