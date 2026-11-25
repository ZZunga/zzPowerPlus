"""
make_assets.py - Connect IQ 스토어용 이미지 생성 (zzPowerPlus)

    python store/make_assets.py            -> store/images/*.png

  cover.png              앱 아이콘(대표 이미지) 500x500, 둘레 10px 여백, 투명 배경
  hero_ko.png / _en.png  히어로 1440x720 (한국어·영어)
  screen{1..5}.png       화면 이미지 500x500 (영어) (업로드 한도 150KB 이하로 저장)

화면 안의 데이터 필드는 tools/preview.py 렌더러로 그린다
(= 앱과 같은 비트맵 폰트·같은 배치 계산). Pillow 필요. zzWeatherPlus/store/make_assets.py 와 같은 틀.
"""
import io, math, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
import preview as pv  # noqa: E402

OUT = os.path.join(HERE, "images")
os.makedirs(OUT, exist_ok=True)

# ---- 글꼴 -------------------------------------------------------------------
def _find_font(cands, want="KR"):
    for path in cands:
        if not os.path.exists(path):
            continue
        if path.endswith(".ttc"):
            for i in range(10):
                try:
                    f = ImageFont.truetype(path, 20, index=i)
                    if want in " ".join(f.getname()):
                        return path, i
                except OSError:
                    break
        else:
            return path, 0
    raise SystemExit("한글 글꼴을 찾을 수 없음: " + ", ".join(cands))

KR_BOLD = _find_font(["/usr/share/fonts/opentype/noto/NotoSansCJK-Black.ttc",
                      "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
                      "C:/Windows/Fonts/malgunbd.ttf"])
KR_REG = _find_font(["/usr/share/fonts/opentype/noto/NotoSansCJK-Medium.ttc",
                     "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
                     "C:/Windows/Fonts/malgun.ttf"])
TITILLIUM = os.path.join(ROOT, "tools", "ttf", "TitilliumWeb-Bold.ttf")

def kb(size): return ImageFont.truetype(KR_BOLD[0], size, index=KR_BOLD[1])
def kr(size): return ImageFont.truetype(KR_REG[0], size, index=KR_REG[1])
def ti(size): return ImageFont.truetype(TITILLIUM, size)

RED = (255, 85, 0)
BLUE_LINE = (0, 120, 215)

def device(screen, side=16, top=22, bottom=30, radius=26):
    """화면 둘레에 무광 검정 사이클 컴퓨터 본체를 그린다 (로고 없음)."""
    sw, sh = screen.size
    W, H = sw + side * 2, sh + top + bottom
    ss = 3
    body = Image.new("RGBA", (W * ss, H * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    d.rounded_rectangle([0, 0, W * ss - 1, H * ss - 1], radius=radius * ss, fill=(28, 30, 34, 255))
    d.rounded_rectangle([3 * ss, 3 * ss, W * ss - 3 * ss, H * ss - 3 * ss], radius=(radius - 3) * ss,
                        outline=(58, 62, 70, 255), width=2 * ss)
    d.rounded_rectangle([(side - 4) * ss, (top - 4) * ss, (side + sw + 4) * ss, (top + sh + 4) * ss],
                        radius=6 * ss, fill=(8, 9, 11, 255))
    body = body.resize((W, H), Image.LANCZOS)
    body.paste(screen, (side, top))
    # 유리 반사 한 줄
    gl = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gl)
    gd.polygon([(side, top), (side + sw * 0.55, top), (side + sw * 0.25, top + sh), (side, top + sh)],
               fill=(255, 255, 255, 14))
    body.alpha_composite(gl)
    return body


def shadowed(img, blur=18, offset=(0, 14), alpha=110):
    pad = blur * 3
    W, H = img.size
    out = Image.new("RGBA", (W + pad * 2, H + pad * 2), (0, 0, 0, 0))
    sh = Image.new("RGBA", out.size, (0, 0, 0, 0))
    mask = img.split()[3].point(lambda a: a * alpha // 255)
    sh.paste(Image.new("RGBA", img.size, (0, 0, 0, 255)), (pad + offset[0], pad + offset[1]), mask)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    out.alpha_composite(sh)
    out.alpha_composite(img, (pad, pad))
    return out, pad


def gradient(W, H, top, bottom):
    g = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / max(1, H - 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((W, H)).convert("RGBA")


def save_png(img, name, limit_kb):
    path = os.path.join(OUT, name)
    rgb = img
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    if limit_kb and buf.tell() > limit_kb * 1024:
        has_alpha = img.mode == "RGBA"
        for colors in (256, 192, 128):
            q = img.convert("RGBA").quantize(colors=colors, method=Image.FASTOCTREE, dither=Image.FLOYDSTEINBERG)
            buf = io.BytesIO()
            q.save(buf, "PNG", optimize=True)
            if buf.tell() <= limit_kb * 1024:
                break
    with open(path, "wb") as f:
        f.write(buf.getvalue())
    print("  %-18s %4dx%-4d %6.1f KB" % (name, img.size[0], img.size[1], buf.tell() / 1024))



# ---- 화면 합성 ------------------------------------------------------------------
def page(rows, sw, sh, dark, solid=False, zone_color=False):
    """rows: [ (h, [ cell, ... ]), ... ]  cell = (w, power, zone, avg, ratios[, ptype]) -> 기기 화면"""
    pv.SCREEN_W[0] = sw
    bg = (23, 24, 29) if (dark and sw >= 480) else ((0, 0, 0) if dark else (255, 255, 255))
    img = Image.new("RGB", (sw, sh), bg)
    dr = ImageDraw.Draw(img)
    lw = 2 if sw >= 480 else 1
    y = 0
    for ri, (h, cells) in enumerate(rows):
        x = 0
        for ci, c in enumerate(cells):
            w, hr, zone, avg, ratios = c[:5]
            pt = c[5] if len(c) > 5 else None
            an = False
            if pt is None:
                an = True
            else:
                pv.PTYPE[:] = list(pt)
            tile = pv.render(w, h, hr, zone, avg, ratios, dark=dark, solid=solid, zone_color=zone_color, analyzing=an)
            img.paste(tile, (x, y))
            x += w
            if ci < len(cells) - 1:
                dr.line([x, y, x, y + h - 1], fill=BLUE_LINE, width=lw)
                x += lw
        y += h
        if ri < len(rows) - 1:
            dr.line([0, y, sw, y], fill=BLUE_LINE, width=lw)
            y += lw
    return img


# 존별 시간 비율 예시 (Z1..Z7) + 운동 형태 (키, 한글, 영문)
R_SST  = [0.15, 0.25, 0.24, 0.29, 0.04, 0.02, 0.01]
R_POL  = [0.24, 0.55, 0.03, 0.04, 0.12, 0.01, 0.01]
R_BASE = [0.25, 0.62, 0.09, 0.03, 0.01, 0.00, 0.00]
R_RACE = [0.12, 0.12, 0.13, 0.20, 0.20, 0.15, 0.08]
R_VO2  = [0.20, 0.30, 0.05, 0.06, 0.33, 0.04, 0.02]
T_SST  = ("SST", "스윗스팟", "Sweet Spot")
T_POL  = ("POL", "양극화", "Polarized")
T_BASE = ("BASE", "베이스", "Base")
T_RACE = ("RACE", "레이스 페이스", "Race Pace")
T_VO2  = ("VO2MAX", "최대산소 인터벌", "VO2max Intervals")


# 10분할 (5줄 x 2칸) 칸 값 예시: (파워, 존, 평균)
VALS10 = [(98, 1.8, 141), (245, 4.3, 198), (182, 3.4, 176), (312, 5.6, 205),
          (1250, 7.9, 210), (156, 2.8, 150), (268, 5.1, 201), (121, 2.1, 120),
          (205, 3.9, 188), (412, 6.4, 215)]


def ten(sw, sh, ratios, vals=VALS10):
    """Garmin 10필드 레이아웃: 5줄 x 2칸, 칸 사이 구분선 포함해 화면을 꽉 채움"""
    lw = 2 if sw >= 480 else 1
    hs = [(sh - 4 * lw) // 5] * 5
    hs[-1] += (sh - 4 * lw) - sum(hs)
    w1 = (sw - lw) // 2
    w2 = sw - lw - w1
    rows = []
    for i, h in enumerate(hs):
        a, b = vals[2 * i], vals[2 * i + 1]
        rows.append((h, [(w1, a[0], a[1], a[2], ratios), (w2, b[0], b[1], b[2], ratios)]))
    return rows


def page_overview_840(dark=False):          # 246x322: 10분할
    return page(ten(246, 322, R_SST), 246, 322, dark)


def page_ten_850(dark=True):                # 420x600: 10분할 (검정 배경, 채움 막대)
    return page(ten(420, 600, R_RACE), 420, 600, dark, solid=True)


def page_type_540(dark=False):              # 246x322: 넓고 높은 칸 운동 형태
    return page([
        (160, [(246, 238, 4.1, 201, R_SST, T_SST)]),
        (80, [(122, 182, 3.4, 176, R_SST), (123, 312, 5.6, 205, R_SST)]),
        (80, [(246, 245, 4.3, 198, R_SST)]),
    ], 246, 322, dark)


def page_type_1050(dark=True):              # 480x800: 운동 형태 + 넓은 칸 + 10필드 칸
    return page([
        (399, [(480, 165, 2.6, 172, R_POL, T_POL)]),
        (199, [(480, 312, 5.6, 205, R_POL)]),
        (198, [(239, 1250, 7.9, 210, R_POL), (239, 182, 3.4, 176, R_POL)]),
    ], 480, 800, dark)


def page_cells_1040(dark=False):            # 282x470: 10분할, 파워존 색
    return page(ten(282, 470, R_VO2), 282, 470, dark, zone_color=True)


# ---- 1) 대표 이미지 500x500 --------------------------------------------------------
def make_cover():
    S = 4
    W = 500 * S
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    p = 10 * S
    d.rounded_rectangle([p, p, W - p - 1, W - p - 1], radius=34 * S, fill=(26, 30, 39, 255))
    sx0, sy0, sx1, sy1 = 58 * S, 50 * S, 442 * S, 318 * S
    d.rounded_rectangle([sx0, sy0, sx1, sy1], radius=22 * S, fill=(244, 244, 244, 255))
    ink = (20, 20, 20, 255)
    zc = [(85, 85, 85), (0, 0, 255), (0, 170, 0), (255, 85, 0), (170, 0, 0)]

    zc = [(85, 85, 85), (0, 0, 255), (0, 170, 0), (255, 170, 0), (255, 85, 0), (170, 0, 0), (170, 0, 255)]
    # 아래: 존별 시간 히스토그램 (줄무늬) + 7존 띠
    bx0, bx1, base = sx0 + 22 * S, sx1 - 22 * S, sy1 - 30 * S
    ratios = [0.15, 0.30, 0.20, 0.22, 0.08, 0.04, 0.01]
    cw = (bx1 - bx0) / 7
    for i, r in enumerate(ratios):
        x0, x1 = bx0 + cw * i + 3 * S, bx0 + cw * (i + 1) - 3 * S
        d.rectangle([x0 - 3 * S, base, x1 + 3 * S, base + 9 * S], fill=zc[i] + (255,))
        top = base - r * 200 * S
        y = base - 6 * S
        while y >= top:
            d.rectangle([x0, y, x1, y + 2 * S], fill=zc[i] + (255,))
            y -= 7 * S
    # 위: 번개 + 존 번호(왼쪽 위), 큰 파워 + 단위 W (앱의 10필드 칸 배치)
    k = 56 * S / 512
    hx, hy = sx0 + 26 * S, sy0 + 18 * S
    d.polygon([(hx + px * k, hy + py * k) for px, py in pv.BOLT], fill=(255, 85, 0, 255))
    d.text((hx + 58 * S, hy + 30 * S), "4", font=ti(56 * S), fill=zc[3] + (255,), anchor="lm")
    big = ti(132 * S)
    unit = ti(40 * S)
    ux = sx1 - 22 * S
    vy = sy0 + 196 * S
    d.text((ux, vy - 58 * S), "W", font=unit, fill=ink, anchor="rs")
    uw = d.textlength("W", font=unit)
    d.text((ux - uw - 10 * S, vy), "245", font=big, fill=ink, anchor="rs")

    d.text((W / 2, 384 * S), "zzPowerPlus", font=ti(64 * S), fill=(255, 255, 255, 255), anchor="mm")
    cap = "POWER  /  ZONE  /  TRAINING TYPE"
    cf = ti(19 * S)
    spacing = 1.6 * S
    total = sum(d.textlength(ch, font=cf) + spacing for ch in cap) - spacing
    cxp = W / 2 - total / 2
    for ch in cap:
        d.text((cxp, 446 * S), ch, font=cf, fill=(255, 140, 70, 255), anchor="lm")
        cxp += d.textlength(ch, font=cf) + spacing
    img = img.resize((500, 500), Image.LANCZOS)
    save_png(img, "cover.png", 300)


# ---- 2) 히어로 1440x720 ------------------------------------------------------------
HERO_TXT = {
    "ko": dict(kicker="Garmin Edge 데이터 필드",
               title="zz파워", tag="파워 · 파워존 · 존별 시간 · 운동 형태",
               bullets=[((255, 85, 0), "3초 파워, NP · IF · TSS까지 한 칸에"),
                        ((0, 170, 255), "7존 시간 히스토그램과 운동 형태 판정"),
                        ((255, 170, 0), "큰 Titillium 숫자, 1000W 넘으면 kW로")],
               devices="Edge 540 · 550 · 840 · 850 · 1040 · 1050 · 1060"),
    "en": dict(kicker="Garmin Edge Data Field",
               title="zzPower", tag="Power · Zone · Time in Zone · Training Type",
               bullets=[((255, 85, 0), "3s power with NP, IF and TSS"),
                        ((0, 170, 255), "7-zone histogram and training type"),
                        ((255, 170, 0), "Big Titillium digits, kW above 1000 W")],
               devices="Edge 540 · 550 · 840 · 850 · 1040 · 1050 · 1060"),
}


def pulse_line(img, color):
    """배경 장식: 파워 그래프처럼 들쭉날쭉한 계단 선 (인터벌)"""
    import random
    rnd = random.Random(7)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    W, H = img.size
    base = 600
    pts, x = [], -20
    while x < W + 40:
        hi = rnd.random() < 0.25
        v = rnd.randint(110, 170) if hi else rnd.randint(30, 70)
        wseg = rnd.randint(40, 90) if hi else rnd.randint(20, 60)
        pts += [(x, base - v), (x + wseg, base - v)]
        x += wseg
    d.line(pts, fill=color + (40,), width=4)
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(1)))


def make_hero(lang):
    pv.LANG[0] = lang
    t = HERO_TXT[lang]
    W, H = 1440, 720
    img = gradient(W, H, (34, 20, 12), (12, 9, 8))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([820, -120, 1620, 700], fill=(230, 90, 20, 60))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(120)))
    pulse_line(img, (255, 140, 60))

    big = device(page_type_1050(dark=True), side=22, top=30, bottom=40, radius=34)
    big = big.resize((int(big.width * 0.70), int(big.height * 0.70)), Image.LANCZOS)
    small = device(page_overview_840(dark=False), side=16, top=22, bottom=30, radius=26)
    small = small.resize((int(small.width * 1.12), int(small.height * 1.12)), Image.LANCZOS)
    b, bp = shadowed(big, blur=22, offset=(0, 18), alpha=150)
    s_, sp = shadowed(small, blur=18, offset=(0, 14), alpha=170)
    img.alpha_composite(b, (1040 - bp, 52 - bp))
    img.alpha_composite(s_, (800 - sp, 222 - sp))

    d = ImageDraw.Draw(img)
    x = 96
    d.text((x, 150), t["kicker"], font=kr(30), fill=(240, 185, 150))
    if lang == "ko":
        f = kb(104)
        d.text((x - 4, 186), t["title"], font=f, fill=(255, 255, 255))
    else:
        f = ti(118)
        d.text((x - 4, 168), t["title"], font=f, fill=(255, 255, 255))
    tw_ = d.textlength(t["title"], font=f)
    d.text((x + tw_ + 2, 168 if lang == "ko" else 160), "+", font=ti(128), fill=RED)
    tag_f = kb(34) if lang == "ko" else ti(38)
    while d.textlength(t["tag"], font=tag_f) > 680:
        tag_f = kb(tag_f.size - 1) if lang == "ko" else ti(tag_f.size - 1)
    d.text((x, 336), t["tag"], font=tag_f, fill=(250, 232, 220))
    y = 418
    for color, line in t["bullets"]:
        d.ellipse([x, y + 12, x + 14, y + 26], fill=color)
        d.text((x + 30, y), line, font=kr(27) if lang == "ko" else ti(30), fill=(248, 236, 228))
        y += 52
    d.text((x, 610), t["devices"], font=kr(22) if lang == "ko" else ti(24), fill=(195, 150, 120))
    save_png(img.convert("RGB"), "hero_%s.png" % lang, 0)


# ---- 3) 화면 이미지 500x500 ----------------------------------------------------------
SCREENS = [
    ("screen1", page_overview_840, False,
     ("파워 · 파워존 · 존별 시간을 한 칸에", "10분할 한 칸에서도 큰 숫자"),
     ("Power, zone and time in zone", "Big digits even in one slot of a 10-field layout")),
    ("screen2", page_type_1050, True,
     ("넓고 높은 칸에서 운동 형태 판정", "존별 시간으로 SST, VO2MAX, POL 등 13가지"),
     ("Training type in large wide fields", "13 types from your time in zone: SST, VO2MAX, POL...")),
    ("screen3", page_type_540, False,
     ("파워 바로 아래에 운동 형태", "기록 10분부터, 10초마다 다시 판정"),
     ("Training type under your power", "From 10 minutes, updated every 10 seconds")),
    ("screen4", page_cells_1040, False,
     ("7존 색과 위치 화살표", "1000W 이상은 1.25 kW로 크게"),
     ("7 zone colors and position arrow", "Above 1000 W shown as 1.25 kW, same big size")),
    ("screen5", page_ten_850, True,
     ("3초 파워, 평균 · NP · IF · TSS", "줄무늬 또는 채움 히스토그램 선택"),
     ("3s power with AVG, NP, IF or TSS", "Striped or solid histogram bars")),
]


def make_screen(name, page_fn, dark, cap, lang):
    pv.LANG[0] = lang
    W = 500
    img = gradient(W, W, (242, 245, 250), (222, 229, 240)) if not dark else gradient(W, W, (36, 24, 16), (12, 10, 9))
    d = ImageDraw.Draw(img)
    title_c = (20, 30, 48) if not dark else (255, 255, 255)
    sub_c = (80, 92, 112) if not dark else (215, 185, 165)

    def fit(make, size, text, maxw=468):
        while size > 12 and d.textlength(text, font=make(size)) > maxw:
            size -= 1
        return make(size)
    tf = fit(kb, 25, cap[0]) if lang == "ko" else fit(ti, 28, cap[0])
    sf = fit(kr, 16, cap[1]) if lang == "ko" else fit(ti, 19, cap[1])
    d.text((W / 2, 30), cap[0], font=tf, fill=title_c, anchor="mm")
    d.text((W / 2, 62), cap[1], font=sf, fill=sub_c, anchor="mm")

    scr = page_fn(dark)
    if scr.height > 340:   # 1040/850/1050: 축소
        dev = device(scr, side=22, top=30, bottom=40, radius=34)
        k = 400 / dev.height
        dev = dev.resize((int(dev.width * k), int(dev.height * k)), Image.LANCZOS)
    else:                  # 540/840: 실제 픽셀 그대로 (비트맵 폰트 선명)
        dev = device(scr)
    sh, sp = shadowed(dev, blur=12, offset=(0, 8), alpha=120)
    img.alpha_composite(sh, ((W - dev.width) // 2 - sp, 88 - sp))
    save_png(img.convert("RGB"), "%s.png" % name, 150)


def main():
    print("store/images:")
    make_cover()
    # 히어로는 한국어·영어 두 장, 화면 5장은 영어만
    make_hero("ko")
    make_hero("en")
    for name, fn, dark, cko, cen in SCREENS:
        make_screen(name, fn, dark, cen, "en")


if __name__ == "__main__":
    main()
