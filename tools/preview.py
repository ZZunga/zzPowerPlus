"""
preview.py - zzPowerPlus 레이아웃 미리보기 (실제 비트맵 폰트로 렌더)

    python tools/preview.py            -> tools/preview.png

source/Layout.mc + source/zzPowerPlusView.mc 의 배치 로직을 그대로 옮긴 것.
View 쪽 레이아웃을 고치면 여기도 같이 맞춘다. (Pillow 필요: pip install pillow)
"""
import os, re
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = os.path.join(ROOT, "resources", "fonts")

PX = [18, 24, 30, 38, 48, 60, 76, 96, 120, 150, 190]
ADV = [10, 13, 17, 21, 27, 34, 43, 54, 67, 84, 106]
CAP = [14, 18, 22, 27, 34, 42, 53, 67, 83, 103, 131]
N = len(PX)

BOLT = [(349, 45), (339, 6), (299, 8), (43, 232), (34, 267), (64, 288), (176, 288), (99, 467), (109, 506), (149, 504), (405, 280), (414, 245), (384, 224), (272, 224)]
HEART = [[93, 504], [446, 833], [471, 849], [500, 854], [529, 849], [554, 833],
        [907, 504], [947, 458], [976, 406], [994, 350], [1000, 290], [1000, 278],
        [992, 212], [969, 151], [934, 98], [887, 54], [831, 22], [767, 3],
        [700, 0], [636, 13], [576, 40], [523, 81], [500, 104], [477, 81],
        [424, 40], [364, 13], [300, 0], [233, 3], [169, 22], [113, 54],
        [66, 98], [31, 151], [8, 212], [0, 278], [0, 290], [6, 350],
        [24, 406], [53, 458]]


def hexrgb(v):
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


# Garmin Graphics 상수 값: DK_GRAY 555555 DK_BLUE 0000FF DK_GREEN 00AA00 ORANGE FF5500 DK_RED AA0000
#                        LT_GRAY AAAAAA BLUE 00AAFF GREEN 00FF00 YELLOW FFAA00 RED FF0000
NZ = 7
ZONE_LIGHT = [0x555555, 0x0000FF, 0x00AA00, 0xFFAA00, 0xFF5500, 0xAA0000, 0xAA00FF]
ZONE_DARK = [0xAAAAAA, 0x00AAFF, 0x00FF00, 0xFFAA00, 0xFF5500, 0xFF0000, 0xFF00FF]
SOLID_LIGHT = [0xDDDDDD, 0xD0D0FF, 0xCCEECC, 0xFFEECC, 0xFFDCCC, 0xEECCCC, 0xEED0FF]
SOLID_DARK = [0x333333, 0x0A2A40, 0x0A3A0A, 0x40380A, 0x40250A, 0x4D0A0A, 0x3A0A40]


class BmFont:
    def __init__(self, name):
        self.chars = {}
        with open(os.path.join(FONTS, name + ".fnt")) as f:
            for line in f:
                if line.startswith("char "):
                    kv = dict(re.findall(r"(\w+)=(-?\d+)", line))
                    self.chars[int(kv["id"])] = {k: int(v) for k, v in kv.items()}
        p0 = os.path.join(FONTS, name + "_0.png")
        im = Image.open(p0 if os.path.exists(p0) else os.path.join(FONTS, name + ".png"))
        if im.mode == "L":                       # Plus 시리즈 형식 (L 모드, 밝기 = 알파)
            im = Image.merge("RGBA", (im, im, im, im))
        self.sheet = im.convert("RGBA")

    def width(self, s):
        return sum(self.chars.get(ord(c), {"xadvance": 0})["xadvance"] for c in s)

    def draw(self, img, x, y, s, color, just="left"):
        if just == "center":
            x -= self.width(s) / 2
        elif just == "right":
            x -= self.width(s)
        x = int(round(x)); y = int(round(y))
        for c in s:
            g = self.chars.get(ord(c))
            if not g:
                continue
            if g["width"] > 0:
                a = self.sheet.crop((g["x"], g["y"], g["x"] + g["width"], g["y"] + g["height"])).split()[3]
                img.paste(Image.new("RGB", a.size, color), (x + g["xoffset"], y + g["yoffset"]), a)
            x += g["xadvance"]


_fc = {}


def font(i):
    if i not in _fc:
        _fc[i] = BmFont("num-%d" % PX[i])
    return _fc[i]


def pick(maxW, maxH, digits):
    idx = 0
    for i in range(N):
        if ADV[i] * digits <= maxW and CAP[i] <= maxH:
            idx = i
        else:
            break
    return idx


UNIT_CAP = [7, 7, 9, 11, 14, 17, 21, 27, 33, 41, 52]
UNIT_BPW = [10, 10, 14, 16, 20, 26, 32, 42, 52, 64, 82]
UNIT_PX = [9, 9, 12, 14, 19, 23, 29, 38, 47, 59, 75]


def ufont(i):
    k = ("u", i)
    if k not in _fc:
        _fc[k] = BmFont("unit-%d" % UNIT_PX[i])
    return _fc[k]
WIDE_VCAP = [35, 42, 63, 72]
WIDE_TCAP = [13, 15, 23, 26]
WIDE_LCAP = [10, 12, 18, 21]
WIDE_DIRS = ["resources", "resources-edge1040", "resources-edge550", "resources-edge1050"]


class WFont(BmFont):
    def __init__(self, path):
        global FONTS
        old = FONTS
        FONTS = os.path.dirname(path)
        BmFont.__init__(self, os.path.basename(path)[:-4])
        FONTS = old


C10_MCAP = [34, 42, 65, 74]; C10_MADV = [28, 35, 54, 61]
C10_SCAP = [20, 24, 36, 41]; C10_SADV = [16, 19, 29, 33]
C10_UMCAP = [8, 10, 14, 16]; C10_UMBP = [12, 16, 22, 26]
TID_PAD = [3, 3, 4, 5]
TINY_CAP = 11
C10_USCAP = [8, 10, 14, 16]; C10_USBP = [10, 14, 20, 24]
TID_KEYS = ["HVLI", "HIT", "PRMD", "R.PRMD", "THRD", "POL", "R.POL", "EVEN"]
TID_KO = ["저강도 고볼륨", "고강도 인터벌", "피라미드", "역피라미드", "역치", "양극화", "역양극화", "균등"]
TID_EN = ["High Volume Low Intensity", "High Intensity", "Pyramidal", "Reverse Pyramidal", "Threshold",
          "Polarized", "Reverse Polarized", "Even"]
TID_DIST = [[35, 55, 5, 2, 3], [20, 20, 5, 5, 50], [20, 55, 15, 5, 5], [3, 7, 10, 30, 50],
            [10, 35, 25, 25, 5], [25, 55, 2, 3, 15], [10, 10, 5, 15, 60], [20, 20, 20, 20, 20]]
LANG = ["ko"]
PTYPE = ["SST", "스윗스팟", "Sweet Spot"]


def tid_classify(ratios):
    pct = [int(r * 1000) for r in ratios]
    best, bs = 0, -1
    for m, d in enumerate(TID_DIST):
        sc = sum(min(pct[z], d[z] * 10) for z in range(5))
        if sc > bs:
            best, bs = m, sc
    return best, (bs + 5) // 10


def fam_of(sw):
    return 3 if sw >= 470 else 2 if sw >= 400 else 1 if sw >= 270 else 0


FONT_IDS = {"wideval": "WideVal", "widetitle": "WideTitle", "widelabel": "WideLabel", "tidlabel": "TidLabel",
            "c10main": "C10Main", "c10sub": "C10Sub", "c10unitmain": "C10UnitMain", "c10unitsub": "C10UnitSub",
            "numtiny": "NumTiny"}


def wide_font(fam, kind):
    """fonts.xml 의 id 로 찾음 (기기 폴더 → 기본 resources 순)"""
    key = (fam, kind)
    if key not in _fc:
        fid = FONT_IDS[kind]
        for d in (WIDE_DIRS[fam], "resources"):
            fd = os.path.join(ROOT, d, "fonts")
            x = open(os.path.join(fd, "fonts.xml"), encoding="utf-8").read()
            m = re.search(r'<font id="%s" filename="([^"]+)"' % fid, x)
            if m:
                _fc[key] = WFont(os.path.join(fd, m.group(1)))
                break
    return _fc[key]


def unit_idx(mi):
    return mi


def pick_unit(maxW, maxH, ug):
    idx = 0
    for i in range(N):
        u = unit_idx(i)
        if ADV[i] * 3 + ug + UNIT_BPW[u] <= maxW and CAP[i] <= maxH:
            idx = i
    return idx


def init_hist(f, w, h, inset, hist=True, pct=True):
    f.update(stripH=0, pctIdx=-1)
    if hist:
        sh = max(3, min(8, int(h / 28)))
        f.update(stripH=sh, histBase=h - sh, histTop=inset if h >= 60 else 0, hatch=max(3, int(w / 82)))
        if pct and h >= 70:
            pi = 1 if w >= 230 else 0
            if ADV[pi] * 3.6 <= w // 7:
                f["pctIdx"] = pi


def compute(w, h, icon=True, sec=True, dec=True):
    sw = SCREEN_W[0]; k = fam_of(sw)
    f = dict(w=w, h=h, wide=False, iconSize=0, zoneIdx=-1, secIdx=-1, fam=k, c10=False, zoneDec=True)
    L = max(2, int(w * 0.05 + 0.5)); T = max(2, int(h * 0.05 + 0.5))
    f["inset"] = L
    init_hist(f, w, h, T, pct=False)
    ug = max(2, int(w * 0.02 + 0.5)); R = w - L
    B = value_bottom(f, h, T)
    vg = max(2, int(h * 0.04 + 0.5))
    hasSec = sec and w >= 80 and h >= 40
    hasIcon = icon and w >= 64 and h >= 40
    mainW = C10_MADV[k] * 3 + ug + C10_UMBP[k]
    secW = (C10_SADV[k] * 3 + ug + C10_USBP[k]) if hasSec else 0
    topH = (C10_SCAP[k] + vg) if (hasIcon or hasSec) else 0
    bFull = h - max(f["stripH"], T)
    b2 = value_bottom(f, h, T, 0.02)
    if T + topH + C10_MCAP[k] > B and T + topH + C10_MCAP[k] <= b2:
        B = b2
    if T + topH + C10_MCAP[k] > B and T + topH + C10_MCAP[k] <= bFull:
        B = bFull
    if mainW <= R - L and secW <= R - L and T + topH + C10_MCAP[k] <= B:
        f.update(c10=True, mainCap=C10_MCAP[k], unitCap=C10_UMCAP[k], subCap=C10_SCAP[k], subUnitCap=C10_USCAP[k],
                 mainX=R - C10_UMBP[k] - ug)
        if hasSec:
            f.update(secIdx=0, secRight=R - C10_USBP[k] - ug)
        sadv = C10_SADV[k]
    else:
        t = 0
        for i in range(N):
            sww = (ADV[i] * 3 + ug + UNIT_BPW[i]) if hasSec else 0
            if sww <= R - L and CAP[i] <= (B - T) / 3:
                t = i
        f.update(zoneIdx=t, subCap=CAP[t], subUnitCap=UNIT_CAP[t], tIdx=t)
        if hasSec:
            f.update(secIdx=t, secRight=R - UNIT_BPW[t] - ug); secW = ADV[t] * 3 + ug + UNIT_BPW[t]
        sadv = ADV[t]
    # 하트 줄 (Layout.placeTop)
    if hasIcon:
        s_ = int(f["subCap"] * 1.0 + 0.5)
        if L + s_ <= R - secW:
            f.update(iconSize=s_, iconX=L, iconY=T + f["subCap"] / 2 - (s_ / 0.875) / 2, zoneX=L + s_ + 2, zoneTop=T, zoneDec=dec)
            f["zoneIdx"] = max(f["zoneIdx"], 0)
            room = R - secW - 2 - f["zoneX"] + int(sadv * 0.4)
            kk = 2.45 if dec else 1.0
            f["zoneNum"] = -1
            for i in range(N - 1, -1, -1):
                if CAP[i] < f["subCap"] and CAP[i] > TINY_CAP and ADV[i] * kk - 1 <= room:
                    f["zoneNum"] = i
                    break
    if not f["c10"]:
        used = (f["subCap"] + vg) if (hasIcon or hasSec) else 0
        mi = pick_unit(R - L, B - T - used, ug)
        f.update(mainIdx=mi, unitIdx=mi, mainCap=CAP[mi], unitCap=UNIT_CAP[mi], mainX=R - UNIT_BPW[mi] - ug)
    f.update(mainBase=B, mainTop=B - f["mainCap"], secTop=T, secBase=T + f["subCap"], R=R)
    return f


def value_bottom(f, h, T, gp=0.05):
    b = h - max(f["stripH"], T)
    if f["stripH"] > 0:
        g = max(1, int(h * gp + 0.5))
        b = min(b, h - f["stripH"] * 2 - 2 - g)
    return b


def compute_wide(w, h, screenW, sec=True, tid=True, icon=True):
    fam = 3 if screenW >= 470 else 2 if screenW >= 400 else 1 if screenW >= 270 else 0
    f = dict(w=w, h=h, wide=True, fam=fam)
    L = int(w * 0.05 + 0.5); T = max(2, int(h * 0.05 + 0.5))
    f["inset"] = L
    tall = h >= w * 0.6
    init_hist(f, w, h, T, pct=tall)
    f["tid"] = False
    vcap, tcap = WIDE_VCAP[fam], WIDE_TCAP[fam]
    vg = max(2, int(h * 0.05)); gap = max(4, int(w * 0.04))
    bottom = value_bottom(f, h, T, 0.02) - 1
    bottom5 = value_bottom(f, h, T, 0.05) - 1
    zcap = C10_SCAP[fam]
    bigH = int(zcap * 1.1 + 0.5)
    f["bigZone"] = icon and (bottom - (T + bigH + vg) >= vcap)
    if not f["bigZone"]:
        zcap = tcap
    f["zcap"] = zcap
    f["tlineH"] = bigH if f["bigZone"] else int(tcap * 1.25 + 0.5)
    f["zoneY"] = T + (f["tlineH"] - zcap) // 2
    f["titleY"] = f["zoneY"] + zcap - tcap
    f["heartSize"] = int(zcap * 1.0 + 0.5) if f["bigZone"] else int(tcap * 1.1 + 0.5)
    f["heartY"] = f["zoneY"] + zcap / 2 - (f["heartSize"] / 0.875) / 2
    f["labelY"] = f["titleY"] + tcap - WIDE_LCAP[fam]
    top = T + f["tlineH"] + vg
    if tid and tall and bottom - top >= vcap:
        lcap = WIDE_LCAP[fam]
        f.update(showTitle=True, tid=True, valIdx=-1, valCap=vcap, valY=top)
        f["tidY"] = top + vcap + int(lcap * 0.7 + 0.5)
        tb = f["tidY"] + int(lcap * 1.75 + 0.5)
        f["histTop"] = max(h // 2, tb + vg)
    elif bottom - top >= vcap:
        vb = bottom5 if bottom5 - top >= vcap else bottom
        f.update(showTitle=True, valIdx=-1, valCap=vcap, valY=top + (vb - top - vcap) // 2)
    else:
        avail = bottom - T
        colW = (w - 2 * L - gap) // 2 if sec else w - 2 * L
        vi = pick(colW, avail, 3.0)
        while vi > 0 and CAP[vi] > vcap:
            vi -= 1
        f.update(showTitle=False, valIdx=vi, valCap=CAP[vi], valY=T + (avail - CAP[vi]) // 2)
    mid = w // 2
    f.update(xc1=(L + mid - gap // 2) // 2, xc2=(mid + gap // 2 + w - L) // 2)
    return f


def hist(img, d, f, ratios, cur, zone, dark, solid, fg, dim, blocks):
    w = f["w"]; zc = ZONE_DARK if dark else ZONE_LIGHT
    base = f["histBase"]; avail = base - f["histTop"]; sh = f["stripH"]
    for i in range(NZ):
        x0 = w * i // NZ; x1 = w * (i + 1) // NZ; col = hexrgb(zc[i])
        d.rectangle([x0, base, x1 - 2, base + sh - 1], fill=col)
        r = ratios[i]; bh = int(avail * r); top = base - bh; bx = x0 + 1; bw = x1 - x0 - 2
        if bh > 0:
            if solid:
                d.rectangle([bx, top, bx + bw - 1, base - 1], fill=hexrgb((SOLID_DARK if dark else SOLID_LIGHT)[i]))
            else:
                y = base - 2
                while y >= top:
                    d.line([bx, y, bx + bw, y], fill=col); y -= f["hatch"]
                d.line([bx, top, bx + bw, top], fill=col)
        if f["pctIdx"] >= 0 and r > 0:
            pf = font(f["pctIdx"]); capH = CAP[f["pctIdx"]]
            label = "%d%%" % int(r * 100 + 0.5)
            ly = top - capH - 2
            if ly < f["histTop"]:
                ly = top + 2
            cx = (x0 + x1) / 2; lw = pf.width(label)
            if not any(cx - lw / 2 < b[2] and cx + lw / 2 > b[0] and ly < b[3] and ly + capH > b[1] for b in blocks):
                pf.draw(img, cx, ly, label, dim, "center")
    if zone is not None:
        a = sh + 2
        cxp = max(a, min(w - a, int(w * max(0.0, zone - 1.0) / NZ)))
        d.polygon([(cxp - a, base - a), (cxp, base), (cxp + a, base - a)], fill=fg)


def heart_poly(d, x, y, s, col):
    k = s / 448.0
    d.polygon([(x + px * k, y + py * k) for px, py in BOLT], fill=col)


def fmt_pow(v):
    if v is None: return "--"
    if v >= 999.5:
        n = int((v + 5) // 10)
        return "%d.%02d" % (n // 100, n % 100)
    return str(int(v + 0.5))


def render(w, h, hr, zone, avg, ratios, dark=False, solid=False, beat=True, zone_color=False, analyzing=False, zdec=False, sec_label="AVG W", sec_unit=True):
    sw = SCREEN_W[0]
    big = sw >= 480
    bg = hexrgb(0x17181D if big else 0) if dark else (255, 255, 255)
    fg = (255, 255, 255) if dark else hexrgb(0x313152 if big else 0)
    dim = (170, 170, 170) if dark else (85, 85, 85)
    heart = hexrgb(0xFFAA00 if dark else 0xFF5500)
    zc = ZONE_DARK if dark else ZONE_LIGHT
    img = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(img)
    cur = max(0, min(NZ - 1, int(zone) - 1)) if zone is not None else -1
    zcol = hexrgb(zc[cur]) if zone and zone >= 1 else dim
    mcol = zcol if (zone_color and zone and zone >= 1) else fg
    zs = "-" if zone is None else ("%d.%d" % (int(zone * 10) // 10, int(zone * 10) % 10) if zdec else str(max(1, int(zone))))
    hs = fmt_pow(hr)
    avs = avg if isinstance(avg, str) else fmt_pow(avg)

    if w > sw * 0.75:
        f = compute_wide(w, h, sw)
        V = wide_font(f["fam"], "wideval") if f["valIdx"] < 0 else font(f["valIdx"])
        blocks = []
        if f["showTitle"]:
            blocks.append([0, 0, w, f["zoneY"] + f["tlineH"]])
        for xc, s in ((f["xc1"], hs), (f["xc2"], avs)):
            vw = V.width(s); blocks.append([xc - vw / 2 - 2, f["valY"] - 2, xc + vw / 2 + 2, f["valY"] + f["valCap"] + 2])
        if f["tid"]:
            blocks.append([0, f["tidY"] - 2, w, f["histTop"]])
        hist(img, d, f, ratios, cur, zone, dark, solid, fg, dim, blocks)
        if f["showTitle"]:
            Ti = wide_font(f["fam"], "widetitle"); La = wide_font(f["fam"], "widelabel")
            tcap = WIDE_TCAP[f["fam"]]; x = f["inset"]; hsz = f["heartSize"]
            if f["bigZone"]:
                ZF = wide_font(f["fam"], "c10sub")
                heart_glyph(img, d, x, f["heartY"], hsz, f["zoneY"], ZF, heart, bg, C10_SCAP[f["fam"]])
            else:
                ZF = Ti
                heart_poly(d, x, f["heartY"], hsz, heart)
            x += hsz + int(tcap * 0.3)
            ZF.draw(img, x, f["zoneY"], zs, zcol); x += ZF.width(zs) + int(tcap * 0.5)
            title = "zzPower+" if w < 300 else "zzPowerPlus"
            if x + Ti.width(title) > w - f["inset"] - La.width(sec_label) - 4:
                title = "zzPower+"
            if x + Ti.width(title) <= w - f["inset"] - La.width(sec_label) - 4:
                Ti.draw(img, x, f["titleY"], title, fg)
            La.draw(img, w - f["inset"], f["labelY"], sec_label, dim, "right")
        V.draw(img, f["xc1"], f["valY"], hs, mcol, "center")
        V.draw(img, f["xc2"], f["valY"], avs, fg, "center")
        if f["tid"]:
            TF = wide_font(f["fam"], "tidlabel")
            lx = f["xc1"] - V.width(hs) / 2
            ty = f["tidY"] - TID_PAD[f["fam"]]
            total = sum(ratios)
            if total <= 0 or analyzing:
                TF.draw(img, lx, ty, "분석 중" if LANG[0] == "ko" else "Analyzing", dim)
            else:
                head, tail = PTYPE[0], " - " + (PTYPE[1] if LANG[0] == "ko" else PTYPE[2])
                if lx + TF.width(head) + TF.width(tail) > w - f["inset"]:
                    lx = f["inset"]
                TF.draw(img, lx, ty, head, fg)
                if lx + TF.width(head) + TF.width(tail) <= w - f["inset"]:
                    TF.draw(img, lx + TF.width(head), ty, tail, dim)
        return img

    f = compute(w, h, dec=zdec)
    k = f["fam"]
    if f["c10"]:
        M = wide_font(k, "c10main"); U = wide_font(k, "c10unitmain")
        S = wide_font(k, "c10sub"); SU = wide_font(k, "c10unitsub")
    else:
        M = font(f["mainIdx"]); U = ufont(f["unitIdx"])
        S = font(f.get("tIdx", 0)); SU = ufont(f.get("tIdx", 0))
    if f["stripH"]:
        hist(img, d, f, ratios, cur, zone, dark, solid, fg, dim, [])
    if f["iconSize"]:
        if f["c10"]:
            heart_glyph(img, d, f["iconX"], f["iconY"], f["iconSize"], f["zoneTop"], S, heart, bg, f["subCap"])
        else:
            heart_poly(d, f["iconX"], f["iconY"], f["iconSize"], heart)
        if f["zoneIdx"] >= 0:
            z = zs if f["zoneDec"] else (str(max(1, int(zone))) if zone else "-")
            right = f["secRight"] - S.width(avs) if f["secIdx"] >= 0 else w - f["inset"]
            room = right - 2 - f["zoneX"] + 1
            cands = [(S, f["subCap"])]
            if f.get("zoneNum", -1) >= 0:
                cands.append((font(f["zoneNum"]), CAP[f["zoneNum"]]))
            cands.append((wide_font(0, "numtiny"), TINY_CAP))
            for zf, zc_ in cands:
                if zf.width(z) <= room:
                    zf.draw(img, f["zoneX"], f["zoneTop"] + f["subCap"] - zc_, z, zcol)
                    break
    if f["secIdx"] >= 0:
        S.draw(img, f["secRight"], f["secTop"], avs, fg, "right")
        if sec_unit:
            unit2(img, SU, f["R"], f["secTop"], f["secBase"], f["subUnitCap"], fg, not isinstance(avg, str) and avg is not None and avg >= 999.5)
    kw = hr is not None and hr >= 999.5
    if kw and f["c10"]:
        n = int((hr + 5) // 10); dec = ".%02d" % (n % 100)
        S.draw(img, f["mainX"], f["mainBase"] - f["subCap"], dec, mcol, "right")
        M.draw(img, f["mainX"] - S.width(dec), f["mainTop"], str(n // 100), mcol, "right")
    else:
        M.draw(img, f["mainX"], f["mainTop"], hs, mcol, "right")
    unit2(img, U, f["R"], f["mainTop"], f["mainBase"], f["unitCap"], fg, kw)
    return img


def unit2(img, U, right, top, base, ucap, fg, kw=False):
    if not kw:
        U.draw(img, right, top, "W", fg, "right"); return
    U.draw(img, right, top, "k", fg, "right")
    U.draw(img, right, min(top + int(ucap * 1.6 + 0.5), base - ucap), "W", fg, "right")


def heart_glyph(img, d, x, y, s, top, font_, col, bg, cap=None):
    h = max(1, int(s / 12))
    heart_poly(d, x - h, y - h, s + 2 * h, bg)
    gh = int(s / 0.875 + 0.5)
    font_.draw(img, x, top + (cap or s) // 2 - gh // 2, "@", col)


def device_column(name, sw, sh, fields, **kw):
    """한 기기 화면을 데이터 필드 여러 칸으로 나눈 그림"""
    SCREEN_W[0] = sw
    scr = Image.new("RGB", (sw, sh), (40, 40, 40))
    y = 0
    for (fw_frac, fh, hr, zone, avg, ratios) in fields:
        row = fw_frac if isinstance(fw_frac, list) else [fw_frac]
        x = 0
        for frac in row:
            fw = int(sw * frac) - (1 if len(row) > 1 else 0)
            scr.paste(render(fw, fh, hr, zone, avg, ratios, **kw), (x, y))
            x += fw + 1
        y += fh + 1
    return scr


SCREEN_W = [246]
R = [0.12, 0.30, 0.18, 0.22, 0.10, 0.05, 0.03]
SST = [0.15, 0.25, 0.24, 0.29, 0.04, 0.02, 0.01]

if __name__ == "__main__":
    shots = []
    # Edge 540/840 246x322 : 넓은 칸 246x62 / 246x79 + 10필드 칸 122x62
    shots.append(device_column("540", 246, 322, [
        (1.0, 79, 245, 4.3, 198, R),
        (1.0, 62, 312, 5.6, 205, R),
        ([0.5, 0.5], 62, 182, 3.4, 176, R),
        ([0.5, 0.5], 62, 1250, 7.9, 210, R),
        (1.0, 52, 145, 2.4, 140, R),
    ]))
    shots.append(device_column("1040", 282, 470, [
        (1.0, 116, 245, 4.3, 198, R),
        (1.0, 92, 156, 2.8, 150, R),
        ([0.5, 0.5], 92, 312, 5.6, 205, R),
        ([0.5, 0.5], 92, 1250, 7.9, 1310, R),
        (1.0, 74, 98, 1.6, 120, R),
    ]))
    shots.append(device_column("850", 420, 600, [
        (1.0, 149, 245, 4.3, 198, R),
        (1.0, 118, 182, 3.4, "0.85", R),
        (1.0, 60, 312, 5.6, 205, R),
        ([0.5, 0.5], 118, 98, 1.6, 120, R),
        ([0.5, 0.5], 150, 1250, 7.9, 210, R),
    ], dark=True))
    shots.append(device_column("1050", 480, 800, [
        (1.0, 200, 245, 4.3, 198, R),
        (1.0, 158, 312, 5.6, 205, R),
        ([0.5, 0.5], 158, 182, 3.4, 176, R),
        ([0.5, 0.5], 158, 1250, 7.9, 210, R),
        (1.0, 120, 145, 2.4, 140, R),
    ], solid=True, zone_color=True))
    shots.append(device_column("540", 246, 322, [
        (1.0, 160, 238, 4.1, 201, SST),
        (1.0, 161, 238, 4.1, 201, SST),
    ]))
    shots.append(device_column("1050", 480, 800, [
        (1.0, 399, 238, 4.1, 201, SST),
        (1.0, 400, 238, 4.1, 201, SST),
    ], dark=True))
    gap = 20
    W = sum(s.width for s in shots) + gap * (len(shots) + 1)
    H = max(s.height for s in shots) + 2 * gap
    out = Image.new("RGB", (W, H), (210, 210, 215))
    x = gap
    for s in shots:
        out.paste(s, (x, gap)); x += s.width + gap
    p = os.path.join(ROOT, "tools", "preview.png")
    out.save(p)
    print(p)
