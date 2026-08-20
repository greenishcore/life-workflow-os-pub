#!/usr/bin/env python3
"""pngink.py — 数一张 PNG 里「不是背景色」的像素占比。

    python3 tools/pngink.py 图.png            # 打印占比，如 0.0512
    python3 tools/pngink.py 图.png --min 0.02 # 低于阈值则退出码 1

**为什么要自己写解码**：快照脚本原本用「文件体积下限」判断整页有没有渲染出来，
但那个判据是错的——实测一张**完全空白的白屏截图有 74KB**（状态栏、圆角、
设备边框就压出这么多），高于当时 40KB 的阈值，守卫等于不存在。
空白图一旦被当成合格基线，之后所有比对都失去意义。

只用标准库（zlib）而不引 Pillow，是为了守住仓库「零外部依赖、离线可用」这条：
快照工具应当 clone 下来就能跑，不该为了数几个像素让人先装个图像库。

只支持模拟器截图会用到的形态：8 位、颜色类型 2（RGB）或 6（RGBA）、非隔行。
遇到别的形态直接报错，不猜。
"""
from __future__ import annotations

import struct
import sys
import zlib


def _chunks(data: bytes):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("不是 PNG")
    i = 8
    while i < len(data):
        (length,) = struct.unpack(">I", data[i:i + 4])
        kind = data[i + 4:i + 8]
        yield kind, data[i + 8:i + 8 + length]
        i += 8 + length + 4          # 跳过 CRC


def _unfilter(raw: bytes, width: int, height: int, channels: int) -> bytearray:
    """还原 PNG 的逐行过滤。5 种过滤器的定义见 PNG 规范第 9 节。"""
    stride = width * channels
    out = bytearray(stride * height)
    prev = bytearray(stride)
    pos = 0
    for y in range(height):
        ftype = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if ftype == 1:                                  # Sub
            for x in range(channels, stride):
                line[x] = (line[x] + line[x - channels]) & 0xFF
        elif ftype == 2:                                # Up
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 0xFF
        elif ftype == 3:                                # Average
            for x in range(stride):
                left = line[x - channels] if x >= channels else 0
                line[x] = (line[x] + ((left + prev[x]) >> 1)) & 0xFF
        elif ftype == 4:                                # Paeth
            for x in range(stride):
                a = line[x - channels] if x >= channels else 0
                b = prev[x]
                c = prev[x - channels] if x >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pred) & 0xFF
        elif ftype != 0:
            raise ValueError(f"未知的行过滤器 {ftype}")
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return out


def ink_ratio(path: str, skip_top: float = 0.0, tolerance: int = 16) -> float:
    """返回「与背景色不同」的像素占比。

    背景色取左上角那个像素——截图的左上角必然是页面底色。
    `skip_top` 跳过顶部若干比例（模拟器截图的状态栏带着时钟，每分钟都在变）。
    """
    data = open(path, "rb").read()
    width = height = depth = color = None
    idat = bytearray()
    for kind, payload in _chunks(data):
        if kind == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", payload)
            if depth != 8 or color not in (2, 6) or interlace != 0:
                raise ValueError(f"只支持 8 位非隔行的 RGB/RGBA，实际 depth={depth} color={color}")
        elif kind == b"IDAT":
            idat += payload
        elif kind == b"IEND":
            break
    if width is None:
        raise ValueError("没有 IHDR")

    channels = 3 if color == 2 else 4
    pixels = _unfilter(zlib.decompress(bytes(idat)), width, height, channels)
    stride = width * channels

    y0 = int(height * skip_top)
    bg = pixels[0:3]
    differing = total = 0
    for y in range(y0, height):
        row = y * stride
        for x in range(0, stride, channels):
            i = row + x
            if (abs(pixels[i] - bg[0]) > tolerance
                    or abs(pixels[i + 1] - bg[1]) > tolerance
                    or abs(pixels[i + 2] - bg[2]) > tolerance):
                differing += 1
            total += 1
    return differing / total if total else 0.0


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    path = argv[0]
    threshold = None
    skip_top = 0.0
    i = 1
    while i < len(argv):
        if argv[i] == "--min" and i + 1 < len(argv):
            threshold = float(argv[i + 1]); i += 2
        elif argv[i] == "--skip-top" and i + 1 < len(argv):
            skip_top = float(argv[i + 1]); i += 2
        else:
            print(f"未知参数：{argv[i]}", file=sys.stderr); return 2
    try:
        ratio = ink_ratio(path, skip_top=skip_top)
    except Exception as exc:                      # 解不开就当成渲染失败，别静默放行
        print(f"❌ {path}: {exc}", file=sys.stderr)
        return 1
    print(f"{ratio:.4f}")
    if threshold is not None and ratio < threshold:
        print(f"❌ {path} 只有 {ratio*100:.2f}% 非背景像素，低于 {threshold*100:.2f}%，"
              f"这一页多半根本没渲染出来", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
