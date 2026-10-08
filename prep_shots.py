#!/usr/bin/env python3
"""Captures -> guide images. Single source of truth; rerunnable from scratch."""
from PIL import Image, ImageFilter, ImageDraw
import os
D="/Users/yuri.dosovitsky/Documents/Private/CalliberX/dev/autokit/captures"
OUT="/private/tmp/claude-502/-Users-yuri-dosovitsky-Documents-Private-CalliberX-dev/7c2a8716-6d49-434f-961c-c0a3154c705f/scratchpad/prep"
S=3448/2000.0
o=lambda *v: tuple(int(x*S) for x in v)          # displayed coords -> original

def build(key, fn, crop, pre_masks=(), post_masks=(), width=1500):
    im=Image.open(f"{D}/{fn}").convert("RGB")
    d=ImageDraw.Draw(im)
    for b in pre_masks:                          # mask before crop (source coords)
        im.paste(im.crop(b).filter(ImageFilter.GaussianBlur(14)), b)
        d.rectangle(b, outline=(150,160,175), width=2)
    im=im.crop(crop)
    im=im.resize((width,int(width*im.height/im.width)), Image.LANCZOS)
    d=ImageDraw.Draw(im)
    for b,col in post_masks:                     # mask after resize (final coords)
        im.paste(im.crop(b).filter(ImageFilter.GaussianBlur(11)), b)
        d.rectangle(b, outline=col, width=2)
    im.save(f"{OUT}/{key}.png")
    im.save(f"{OUT}/{key}.webp","WEBP",quality=86,method=6)
    print(f"{key:12s} {im.size}  {os.path.getsize(f'{OUT}/{key}.webp')//1024}KB")

GREY=(150,160,175); DARK=(110,110,110)
build("01-plan",    "Screenshot 2026-09-24 at 20.39.41.png", o(120,245,1880,905))
build("02-os",      "Screenshot 2026-09-24 at 20.43.04.png", o(570,252,1434,752))
build("03-rootpw",  "Screenshot 2026-09-24 at 21.14.22.png", o(320,285,1685,800))
build("04-panel",   "Screenshot 2026-09-24 at 21.32.21.png", o(540,95,1850,400),
      pre_masks=[o(840,357,945,379), o(1466,357,1655,379)],        # IPv4, ssh root@IP
      post_masks=[((134,15,356,39),GREY), ((198,205,416,233),GREY)])  # hostname x2
build("05-terminal","Screenshot 2026-09-24 at 21.32.37.png", o(0,0,790,545),
      post_masks=[((122,960,332,1000),DARK)])                      # hostname in prompt
