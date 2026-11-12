#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) 2026 ZEDEDA, Inc.
"""Regenerate the app icon files for all platforms from the artwork in
app-icon.svg (the geometry is repeated below so that only Pillow is needed).

    python3 src/icons/generate-app-icons.py

Writes:
    src/icons/AppIcon-compiled.icns     macOS bundle icon
    src/icons/eve-imager.ico            Windows executable and installer
    src/icons/rpi-imager.ico            window icon (Qt resource)
    src/linux/icon/eve-imager.png       Linux, 256 px
    src/linux/icon/eve-imager-128.png   Linux, 128 px
"""
import os
from PIL import Image, ImageDraw

NAVY = (0x15, 0x38, 0x4a, 255)
WHITE = (255, 255, 255, 255)
TEAL = (0x5f, 0xd3, 0xcd, 255)

# The Z, in the 128-unit grid of app-icon.svg
OX, OY, K = 34.75, 31.6, 2.6
TOP = [(0, 0), (22.485, 0), (22.485, 4.16279), (0, 4.16279)]
BOTTOM = [(0, 20.7539), (22.5023, 20.7539), (22.5023, 24.9167), (0, 24.9167)]
DIAGONAL = [(5.89564, 20.7539), (22.4875, 4.16211), (16.5721, 4.16211), (0, 20.7539)]


def render(size, inset=0.0):
    """One icon bitmap. `inset` is the transparent margin as a fraction of the
    size (macOS icons leave room around the tile, the others fill the square)."""
    ss = max(4, 2048 // size) if size < 512 else 4      # supersampling factor
    n = size * ss
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m = inset * n
    u = (n - 2 * m) / 128.0                              # pixels per grid unit
    d.rounded_rectangle([m, m, n - m - 1, n - m - 1], radius=28 * u, fill=NAVY)

    def poly(points, colour):
        d.polygon([(m + (OX + x * K) * u, m + (OY + y * K) * u) for x, y in points], fill=colour)

    poly(DIAGONAL, TEAL)
    poly(TOP, WHITE)
    poly(BOTTOM, WHITE)
    return img.resize((size, size), Image.LANCZOS)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    linux = os.path.join(here, "..", "linux", "icon")

    # macOS: 824 px tile on a 1024 px canvas, as in Apple's icon grid
    mac = [render(s, inset=100 / 1024) for s in (1024, 512, 256, 128, 64, 32, 16)]
    mac[0].save(os.path.join(here, "AppIcon-compiled.icns"), append_images=mac[1:])

    ico_sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    ico = [render(s) for s in ico_sizes]
    for name in ("eve-imager.ico", "rpi-imager.ico"):
        ico[-1].save(os.path.join(here, name), sizes=[(s, s) for s in ico_sizes],
                     append_images=ico[:-1])

    render(256).save(os.path.join(linux, "eve-imager.png"))
    render(128).save(os.path.join(linux, "eve-imager-128.png"))


if __name__ == "__main__":
    main()
