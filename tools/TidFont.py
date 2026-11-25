"""
TidFont.py - 운동 형태 줄 폰트 (영문/숫자 = Titillium Web SemiBold, 한글 = Noto Sans KR)

    python tools/TidFont.py <outDir> <capPx>

FntGen.java 와 같은 BMFont 형식:
  - PNG 는 R=G=B=A 회색조 (가장자리 계단 현상 방지)
  - yoffset 은 가장 높은 글자(한글) 윗선 기준 → drawText(x, y) 하면 글자 윗선이 y, 음수 yoffset 없음
    (Connect IQ 가 줄 위로 나간 부분을 잘라내므로)
한글은 글자 높이가 숫자 높이의 1.15 배가 되게 크기를 맞추고 바닥선을 같이 쓴다.
글자 목록은 운동 형태 이름(한/영) + "분석 중" 에 쓰이는 것만 (resources-kor 의 pt* 문자열).
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LATIN = os.path.join(ROOT, "tools", "ttf", "TitilliumWeb-SemiBold.ttf")
KR_CANDS = ["/usr/share/fonts/opentype/noto/NotoSansCJK-Medium.ttc",
            "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
            os.path.join(ROOT, "tools", "ttf", "NotoSansKR-Medium.ttf"),
            "C:/Windows/Fonts/malgun.ttf"]

ASCII = "".join(chr(c) for c in range(32, 127))
HANGUL = "강거고극대도딩라레리린바방벌베복분산상석소스양연윗유은이인일자장중지짧최타터템트팟페포프화회"


def kr_font(size):
    for p in KR_CANDS:
        if not os.path.exists(p):
            continue
        if p.endswith(".ttc"):
            for i in range(12):
                try:
                    f = ImageFont.truetype(p, size, index=i)
                except OSError:
                    break
                if "KR" in " ".join(f.getname()):
                    return f
        else:
            return ImageFont.truetype(p, size)
    raise SystemExit("한글 글꼴을 찾을 수 없음")


def fit_latin(cap):
    px = round(cap / 0.698)
    for _ in range(12):
        f = ImageFont.truetype(LATIN, px)
        b = f.getbbox("0", anchor="ls")
        h = b[3] - b[1]
        if h == cap:
            return f
        px += 1 if h < cap else -1
    return f


def fit_kr(target):
    px = round(target * 1.1)
    for _ in range(20):
        f = kr_font(px)
        b = f.getbbox("고", anchor="ls")
        h = b[3] - b[1]
        if h == target:
            return f
        px += 1 if h < target else -1
    return f


def pad_for(cap):
    return max(3, round(cap * 0.25))


def main(out, cap):
    lat = fit_latin(cap)
    kor = fit_kr(round(cap * 1.15))
    digit_top = lat.getbbox("0", anchor="ls")[1]          # 음수 (바닥선 위)
    glyphs = []
    for ch in ASCII + HANGUL:
        f = kor if ch in HANGUL else lat
        b = f.getbbox(ch, anchor="ls")
        adv = round(f.getlength(ch))
        w, h = b[2] - b[0], b[3] - b[1]
        img = None
        if w > 0 and h > 0 and ch != " ":
            img = Image.new("L", (w, h), 0)
            ImageDraw.Draw(img).text((-b[0], -b[1]), ch, font=f, fill=255, anchor="ls")
        glyphs.append((ch, img, b[0], b[1] - digit_top, adv))
    # Connect IQ 는 줄 윗선(y) 위로 나간 부분을 잘라낸다. 한글은 숫자보다 높아서
    # yoffset 이 음수가 되므로, 가장 높은 글자의 윗선이 0 이 되게 전체를 내린다.
    top = min(g[3] for g in glyphs if g[1])
    shift = -top if top < 0 else 0
    # Connect IQ 는 글자 상자 맨 위 몇 px 도 잘라낸다 (시뮬레이터에서 한글 윗획이 잘림).
    # 위에 여유(PAD)를 두고, 그리는 쪽(zzPowerPlusView)에서 그만큼 위로 올려 그린다 (Layout.TID_PAD).
    shift += pad_for(cap)
    glyphs = [(ch, img, xo, yo + shift, adv) for ch, img, xo, yo, adv in glyphs]
    cap_base = cap + shift
    bottom = max(g[3] + (g[1].height if g[1] else 0) for g in glyphs)
    # 한 줄로 쌓기 (폭 1024 넘으면 줄바꿈)
    maxw, gap, x, y, rowh, sw = 1024, 1, 0, 0, 0, 1
    pos = []
    for ch, img, xo, yo, adv in glyphs:
        w = img.width if img else 0
        hh = img.height if img else 0
        if x + w > maxw:
            x, y, rowh = 0, y + rowh + gap, 0
        pos.append((x, y))
        x += w + gap
        rowh = max(rowh, hh)
        sw = max(sw, x)
    sh = y + rowh
    sheet = Image.new("RGBA", (sw, max(1, sh)), (0, 0, 0, 0))
    lines = []
    for (ch, img, xo, yo, adv), (px, py) in zip(glyphs, pos):
        w = h = 0
        if img:
            w, h = img.size
            rgba = Image.merge("RGBA", (img, img, img, img))   # R=G=B=A
            sheet.paste(rgba, (px, py))
        lines.append("char id=%-5d x=%-4d y=%-4d width=%-4d height=%-4d xoffset=%-4d yoffset=%-4d xadvance=%-4d page=0 chnl=15"
                     % (ord(ch), px, py, w, h, xo if img else 0, yo if img else 0, adv))
    base = "tidlabel-%d" % cap
    os.makedirs(out, exist_ok=True)
    sheet.save(os.path.join(out, base + "_0.png"))
    with open(os.path.join(out, base + ".fnt"), "w", encoding="utf-8") as fp:
        fp.write('info face="TitilliumWeb+NotoSansKR" size=-%d bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=2 padding=0,0,0,0 spacing=1,1 outline=0\n' % lat.size)
        fp.write("common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0\n"
                 % (bottom, cap_base, sw, max(1, sh)))
        fp.write('page id=0 file="%s_0.png"\n' % base)
        fp.write("chars count=%d\n" % len(glyphs))
        fp.write("\n".join(lines) + "\n")
    print("%s cap=%d shift=%d latin_px=%d kr_px=%d sheet=%dx%d" % (base, cap, shift, lat.size, kor.size, sw, sh))


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]))
