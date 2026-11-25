using Toybox.Graphics;

// 데이터 필드 칸 크기에 맞춰 폰트 인덱스와 좌표를 계산한다.
// zzHeartPlus 와 같은 배치 (Plus 시리즈 규칙):
//   - 칸 폭 > 화면 폭 75% 면 넓은 칸 (computeWide), 아니면 좁은 칸 (compute)
//   - 여백 가로/세로 5%, 단위 "W" (1000W 이상은 2단 "k" / "W"). 단위 칸 폭은 심박앱 "bp" 폭 그대로
//   - 숫자 폰트(Num18..Num190)는 zzCadence 크기 표, 넓은 칸 값/타이틀/라벨은 기기별 Wide* 폰트
// 배경에는 존별 시간 % 히스토그램, 맨 아래에 존 색 띠 + 현재 위치 화살표.
module Layout {

    // fonts.xml 의 Num* 폰트와 1:1 대응 (작은 -> 큰). FntGen 재생성 시 출력(px adv cap)으로 동기화.
    const PX  = [ 18, 24, 30, 38, 48, 60, 76, 96, 120, 150, 190 ];
    const ADV = [ 10, 13, 17, 21, 27, 34, 43, 54,  67,  84, 106 ];  // 숫자 1글자 advance(px)
    const CAP = [ 14, 18, 22, 27, 34, 42, 53, 67,  83, 103, 131 ];  // 숫자 높이(px)
    const NFONTS = 11;

    // 넓은 칸 (Plus 시리즈 zzSpeedPlus / zzCadencePlus 와 같은 크기).
    // 화면 폭 246 / 282 / 420 / 480 순. 값 = 숫자 높이(px). 폰트는 기기별 resources 의 WideVal/WideTitle/WideLabel.
    const WIDE_VCAP = [ 35, 42, 63, 72 ];   // 두 값 (같은 크기로 나란히)
    const WIDE_TCAP = [ 13, 15, 23, 26 ];   // 타이틀 "zzPowerPlus" + 존 번호
    const WIDE_LCAP = [ 10, 12, 18, 21 ];   // 오른쪽 위 회색 라벨 "AVG W" / 운동 형태 줄
    // 운동 형태 폰트(TidLabel) 위쪽 여유 px. CIQ 가 글자 상자 맨 위를 잘라내서 둠 (tools/TidFont.py pad_for)
    const TID_PAD   = [  3,  3,  4,  5 ];

    // 좁은 칸 (Plus 시리즈 10필드 칸 크기). 기기별 resources 의 C10* 폰트.
    //   C10Main = 메인 숫자, C10Sub = 보조값·존 번호, C10Unit* = 2단 단위 (각 숫자 높이의 40%)
    const C10_MCAP  = [ 34, 42, 65, 74 ];   // 메인 숫자 높이
    const C10_MADV  = [ 28, 35, 54, 61 ];   // 메인 숫자 1글자 폭
    const C10_SCAP  = [ 20, 24, 36, 41 ];   // 보조값 숫자 높이
    const C10_SADV  = [ 16, 19, 29, 33 ];
    const C10_UMCAP = [  8, 10, 14, 16 ];   // 메인 단위 높이 (보조 단위와 같은 크기)
    const C10_UMBP  = [ 12, 16, 22, 26 ];   // 메인 단위 "bp" 폭
    const C10_USCAP = [  8, 10, 14, 16 ];   // 보조 단위 높이
    const C10_USBP  = [ 10, 14, 20, 24 ];

    // 번개 (power.svg 448x512): 폭 = 높이의 0.875. 좁은 칸 아이콘 폭 = 숫자 높이 (그림 높이 = 숫자 높이의 1.14배)
    const BOLT_AR = 0.875;
    const BOLT_W = 1.0;

    class Frame {
        var w = 0;
        var h = 0;
        var inset = 3;

        // ---- 넓은 칸 전용 (wide == true) ----
        var wide = false;
        var fam = 0;           // WIDE_* 표 인덱스
        var showTitle = true;  // 낮아서 타이틀이 안 들어가면 false (숫자만, Num 폰트 사용)
        var titleY = 0;        // 타이틀 숫자 윗선
        var heartSize = 0;     // 번개 폭
        var titleRight = 0;    // 라벨 오른쪽 끝
        var labelY = 0;
        var tlineH = 0;        // 타이틀 줄 높이
        var valIdx = -1;       // < 0 이면 WideVal, 아니면 Num 폰트 인덱스
        var valCap = 0;
        var valY = 0;          // 값 숫자 윗선
        var xc1 = 0;           // 왼쪽 값(현재 심박) 가운데
        var xc2 = 0;           // 오른쪽 값(보조값) 가운데
        var xcOne = 0;         // 보조값 없을 때 가운데
        var shortTitle = false;
        var bigZone = false;   // true: 번개 + 존 번호를 C10Sub(보조값) 크기로 크게
        var heartY = 0;        // 번개 상자 윗선
        var zoneY = 0;         // 존 번호 윗선

        // ---- 좁은 칸 ----
        var c10 = false;       // true: 기기별 C10* 폰트, false: Num/Unit 폰트(인덱스)
        var mainCap = 0;       // 메인 숫자 높이
        var unitCap = 0;       // 메인 단위 높이
        var subCap = 0;        // 보조값·존 번호 숫자 높이
        var subUnitCap = 0;    // 보조 단위 높이
        var zoneDec = true;    // 존 번호 소수 표시 (폭이 모자라면 정수)

        // ---- 운동 형태 분석 화면 (넓고 높은 칸 + 설정) ----
        var tid = false;
        var tidY = 0;          // 운동 형태 줄 윗선

        // 하단 존 띠 + 히스토그램 영역
        var stripH = 0;        // 존 색 띠 두께
        var histTop = 0;       // 막대가 100% 일 때 위쪽 y
        var histBase = 0;      // 막대 바닥 y (= 띠 위쪽)
        var hatchStep = 3;     // 줄무늬 간격
        var pctIdx = -1;       // < 0 이면 % 라벨 숨김

        var iconSize = 0;      // 0 이면 번개 숨김
        var iconX = 0;
        var iconY = 0;

        var zoneIdx = -1;      // < 0 이면 존 번호 숨김
        var zoneX = 0;
        var zoneTop = 0;
        var zoneNum = -1;      // >= 0 이면 존 번호를 이 Num 폰트(작은 크기)로 소수 표시

        var mainIdx  = 0;      // 메인 심박 폰트 ("188" + 단위 기준)
        var mainX    = 0;      // 숫자 오른쪽 끝 x (오른쪽 정렬)
        var mainTop  = 0;      // 숫자 윗선 y
        var mainBase = 0;      // 숫자 바닥선 y

        var unitIdx = -1;      // 메인 2단 단위("bp"/"m") 폰트
        var unitGap = 3;       // 숫자-단위 간격

        var secIdx      = -1;  // < 0 이면 보조값 숨김
        var secLabelIdx = 0;   // 보조값 2단 단위 폰트
        var secRightX   = 0;   // 보조값 숫자 오른쪽 끝 x
        var secTop      = 0;
        var secLabelTop = 0;   // 보조값 숫자 바닥선 y
    }

    // maxW 안에 digits(소수 허용) 글자, maxH 안에 높이가 들어가는 가장 큰 폰트
    function pick(maxW, maxH, digits) {
        var idx = 0;
        for (var i = 0; i < NFONTS; i++) {
            if (ADV[i] * digits <= maxW && CAP[i] <= maxH) {
                idx = i;
            } else {
                break;
            }
        }
        return idx;
    }

    // 2단 단위 폰트 (Unit*): Num 인덱스와 1:1, 숫자 높이의 40%. FntGen 재생성 시 동기화.
    const UNIT_CAP = [  7,  7,  9, 11, 14, 17, 21, 27, 33, 41, 52 ];   // 단위 글자 높이
    const UNIT_BPW = [ 10, 10, 14, 16, 20, 26, 32, 42, 52, 64, 82 ];   // "bp" 폭 (단위 칸 폭)

    function unitIdxFor(mainIdx) {
        return mainIdx;
    }

    // maxW 안에 "188" + 간격 + 2단 단위, maxH 안에 숫자 높이가 들어가는 가장 큰 폰트
    function pickWithUnit(maxW, maxH, ug) {
        var idx = 0;
        for (var i = 0; i < NFONTS; i++) {
            var u = unitIdxFor(i);
            if (ADV[i] * 3 + ug + UNIT_BPW[u] <= maxW && CAP[i] <= maxH) {
                idx = i;
            }
        }
        return idx;
    }

    // ---- 좁은 칸 (10필드 칸 등) - zzCadencePlus 와 같은 방식 ---------------
    //  [⚡ 4            198 W]   ← 번개 + 존 번호 / 보조값 + 단위 (같은 크기, 같은 윗선)
    //  [          245 W     ]   ← 현재 파워 + 단위 (오른쪽 아래). 1000W 이상은 1.25 k/W
    //  [■■■■■■■■■■■■■■■■■■■■]   ← 존 띠 + 현재 위치 화살표 (+ 배경 히스토그램)
    // 글자 크기는 Plus 시리즈 10필드 칸과 같다 (C10_*). 여백 가로/세로 5%, 숫자-단위 간격 폭의 2%.
    // 칸이 그보다 작으면 Num 폰트 중 들어가는 가장 큰 크기로 줄인다.
    // 존 번호는 소수(2.4)가 안 들어가면 정수(2), 그것도 안 되면 숨긴다.
    function compute(w, h, screenW, wantIcon, wantSec, wantHist, zoneDecimal) {
        var f = new Frame();
        f.w = w;
        f.h = h;
        f.fam = famOf(screenW);

        var L = (w * 0.05 + 0.5).toNumber();
        var T = (h * 0.05 + 0.5).toNumber();
        if (L < 2) { L = 2; }
        if (T < 2) { T = 2; }
        f.inset = L;
        initHist(f, w, h, T, wantHist, false);          // 좁은 칸은 % 숫자 없음
        var ug = (w * 0.02 + 0.5).toNumber();
        if (ug < 2) { ug = 2; }
        f.unitGap = ug;
        var R = w - L;
        var B = valueBottom(f, h, T, 0.05);
        var vg = (h * 0.04 + 0.5).toNumber();
        if (vg < 2) { vg = 2; }
        var hasSec = (wantSec && w >= 80 && h >= 40);
        var hasIcon = (wantIcon && w >= 64 && h >= 40);

        // 1) Plus 시리즈 크기가 들어가는지
        var k = f.fam;
        var mainW = C10_MADV[k] * 3 + ug + C10_UMBP[k];
        var secW = hasSec ? (C10_SADV[k] * 3 + ug + C10_USBP[k]) : 0;
        var topH = (hasIcon || hasSec) ? (C10_SCAP[k] + vg) : 0;
        // 화살표 위 2% 띄우기로 안 들어가면 (540/840 62px, 550/850 118px 칸) 띄우기를 빼고 다시 확인
        var bFull = h - ((f.stripH > T) ? f.stripH : T);
        var b2 = valueBottom(f, h, T, 0.02);
        if (T + topH + C10_MCAP[k] > B && T + topH + C10_MCAP[k] <= b2) { B = b2; }
        if (T + topH + C10_MCAP[k] > B && T + topH + C10_MCAP[k] <= bFull) { B = bFull; }
        if (mainW <= R - L && secW <= R - L && T + topH + C10_MCAP[k] <= B) {
            f.c10 = true;
            f.mainCap = C10_MCAP[k];
            f.unitCap = C10_UMCAP[k];
            f.subCap = C10_SCAP[k];
            f.subUnitCap = C10_USCAP[k];
            f.unitIdx = -1;
            f.secLabelIdx = -1;
            f.mainX = R - C10_UMBP[k] - ug;
            if (hasSec) {
                f.secIdx = 0;                                  // 표시 여부만 (폰트는 C10Sub)
                f.secRightX = R - C10_USBP[k] - ug;
            }
            placeTop(f, L, T, R, hasIcon, hasSec, zoneDecimal, C10_SADV[k], secW);
        } else {
            // 2) 작은 칸: Num 폰트로 줄이기
            var t = 0;
            var topAvail = (B - T) / 3;
            for (var i = 0; i < NFONTS; i++) {
                var sw = hasSec ? (ADV[i] * 3 + ug + UNIT_BPW[i]) : 0;
                if (sw <= R - L && CAP[i] <= topAvail) { t = i; }
            }
            f.zoneIdx = t;
            f.subCap = CAP[t];
            f.subUnitCap = UNIT_CAP[t];
            if (hasSec) {
                f.secIdx = t;
                f.secLabelIdx = t;
                f.secRightX = R - UNIT_BPW[t] - ug;
                secW = ADV[t] * 3 + ug + UNIT_BPW[t];
            }
            placeTop(f, L, T, R, hasIcon, hasSec, zoneDecimal, ADV[t], secW);
            var used = (hasIcon || hasSec) ? (f.subCap + vg) : 0;
            f.mainIdx = pickWithUnit(R - L, B - T - used, ug);
            f.unitIdx = unitIdxFor(f.mainIdx);
            f.mainCap = CAP[f.mainIdx];
            f.unitCap = UNIT_CAP[f.unitIdx];
            f.mainX = R - UNIT_BPW[f.unitIdx] - ug;
        }
        f.mainBase = B;
        f.mainTop = B - f.mainCap;
        f.secTop = T;
        f.secLabelTop = T + f.subCap;                           // 보조값 바닥선
        return f;
    }

    // 번개 줄 배치: 번개(그림 높이 = 보조값 숫자 높이) + 존 번호.
    //  존 번호 글자 크기는 그릴 때 실제 폭으로 고른다 (zzHeartPlusView.drawZone):
    //   보조값 폰트 → 중간 Num 폰트(zoneNum) → NumTiny 순으로 들어가는 가장 큰 것, 바닥선은 보조값과 맞춤.
    //  존 소수 설정 켬: 항상 소수 ("2.4"), 끔: 정수 ("2").
    const TINY_CAP = 11;
    function placeTop(f, L, T, R, hasIcon, hasSec, zoneDecimal, sadv, secW) {
        if (!hasIcon) {
            return;
        }
        var s = (f.subCap * BOLT_W + 0.5).toNumber();          // 번개 폭
        if (L + s > R - secW) {
            return;
        }
        f.iconSize = s;
        f.iconX = L;
        f.iconY = T + f.subCap / 2 - (s / BOLT_AR) / 2;       // 번개 상자 윗선 (가운데 = 숫자 가운데)
        f.zoneX = L + s + 2;
        f.zoneDec = zoneDecimal;
        f.zoneTop = T;
        if (f.zoneIdx < 0) { f.zoneIdx = 0; }
        // 중간 크기 후보: 보조값보다 작은 Num 폰트 중 대략 들어갈 것 (보조값 실제 폭은 그릴 때 확인)
        var room = R - secW - 2 - f.zoneX + (sadv * 0.4).toNumber();
        var k = zoneDecimal ? 2.45 : 1.0;
        f.zoneNum = -1;
        for (var i = NFONTS - 1; i >= 0; i--) {
            if (CAP[i] < f.subCap && CAP[i] > TINY_CAP && ADV[i] * k - 1 <= room) {
                f.zoneNum = i;
                break;
            }
        }
    }

    // 값 숫자 바닥선: 아래 여백(5%), 존 띠가 있으면 띠 위 화살표(높이 = 띠 + 2)보다 칸 높이 gp 만큼 더 위
    //  기본 5% (숫자와 화살표가 붙어 보이지 않게), 칸이 낮아 안 들어가면 2%
    function valueBottom(f, h, T, gp) {
        var b = h - ((f.stripH > T) ? f.stripH : T);
        if (f.stripH > 0) {
            var g = (h * gp + 0.5).toNumber();
            if (g < 1) { g = 1; }
            var a = h - f.stripH * 2 - 2 - g;
            if (a < b) { b = a; }
        }
        return b;
    }

    // 하단 존 띠 / 히스토그램 영역 (두 배치 공통)
    function initHist(f, w, h, inset, wantHist, wantPct) {
        if (wantHist) {
            var sh = (h / 28).toNumber();
            if (sh < 3) { sh = 3; }
            if (sh > 8) { sh = 8; }
            f.stripH = sh;
            f.histBase = h - sh;
            f.histTop = (h >= 60) ? inset : 0;
            var step = (w / 82).toNumber();      // 246px -> 3, 480px -> 5
            if (step < 3) { step = 3; }
            f.hatchStep = step;
            // % 라벨: 막대 한 칸에 "100%" 가 들어가고 칸이 충분히 높을 때만
            if (wantPct && h >= 70) {
                var colW = w / 7;
                var pi = (w >= 230) ? 1 : 0;
                if (ADV[pi] * 3.6 <= colW) {
                    f.pctIdx = pi;
                }
            }
        }
    }

    // ---- 넓은 칸 ----------------------------------------------------------
    //  [⚡ 4 zzPowerPlus                  AVG W]   ← 타이틀 줄 (라벨은 회색)
    //  [     245          |       198         ]   ← 두 값 같은 크기, 남는 높이의 가운데
    //  [■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■]   ← 존 띠 (+ 배경 히스토그램)
    // 여백·간격은 zzCadencePlus 와 같음: 가로/세로 5%, 두 값 사이 4%.
    function famOf(screenW) {
        if (screenW >= 470) { return 3; }
        if (screenW >= 400) { return 2; }
        if (screenW >= 270) { return 1; }
        return 0;
    }

    //  운동 형태 분석 (설정 켬 + 넓고 높은 칸):
    //  [⚡ 4 zzPowerPlus                  AVG W]
    //  [     245          |       198         ]   ← 위쪽 절반: 값은 위로 붙임
    //  [ SST - 스윗스팟                        ]   ← 파워 바로 아래 운동 형태
    //  [ ─────────── 히스토그램 (% 숫자) ──────── ]   ← 아래쪽 절반
    function computeWide(w, h, screenW, wantSec, wantHist, wantPct, wantTid, wantIcon) {
        var f = new Frame();
        f.wide = true;
        f.w = w;
        f.h = h;
        f.fam = famOf(screenW);
        var L = (w * 0.05 + 0.5).toNumber();
        var T = (h * 0.05 + 0.5).toNumber();
        if (T < 2) { T = 2; }
        f.inset = L;
        // % 숫자는 넓고 높은 칸(높이 >= 폭의 60%, 1~2필드 칸)에서만
        var tall = (h >= w * 0.6);
        initHist(f, w, h, T, wantHist, wantPct && tall);

        var vcap = WIDE_VCAP[f.fam];
        var tcap = WIDE_TCAP[f.fam];
        var vg = (h * 0.05).toNumber();
        if (vg < 2) { vg = 2; }
        var gap = (w * 0.04).toNumber();
        if (gap < 4) { gap = 4; }

        // 존 띠는 아래 여백 안에 들어간다 → 타이틀이 들어가는 높이 조건이 zzCadencePlus 와 같다
        var bottom = valueBottom(f, h, T, 0.02) - 1;            // 타이틀·큰 존 번호 판단은 2% 기준 (배치는 그대로)
        var bottom5 = valueBottom(f, h, T, 0.05) - 1;           // 값 위치는 5% 가 들어가면 5% 로

        // 타이틀 줄: 번개 + 존 번호는 좁은 칸 보조값(C10Sub) 크기로 크게. 높이가 모자라면 타이틀 크기로.
        //  앱 이름·라벨은 존 번호와 바닥선을 맞춤.
        var zcap = C10_SCAP[f.fam];
        var bigH = (zcap * 1.1 + 0.5).toNumber();
        f.bigZone = wantIcon && (bottom - (T + bigH + vg) >= vcap);
        if (!f.bigZone) { zcap = tcap; }
        f.tlineH = f.bigZone ? bigH : (tcap * 1.25 + 0.5).toNumber();
        f.zoneY = T + (f.tlineH - zcap) / 2;
        f.titleY = f.zoneY + zcap - tcap;
        f.heartSize = f.bigZone ? (zcap * BOLT_W + 0.5).toNumber()    // 번개 폭 = 존 숫자 높이
                                : (tcap * 1.1 + 0.5).toNumber();
        f.heartY = f.zoneY + zcap / 2 - (f.heartSize / BOLT_AR) / 2;
        f.titleRight = w - L;
        f.labelY = f.titleY + tcap - WIDE_LCAP[f.fam];   // 라벨 바닥선 = 타이틀 바닥선
        f.shortTitle = (w < 300);

        var top = T + f.tlineH + vg;
        if (wantTid && tall && bottom - top >= vcap) {
            // 운동 형태 화면: 값은 타이틀 바로 아래, 그 아래 운동 형태 줄, 히스토그램은 아래쪽 절반
            var lcap = WIDE_LCAP[f.fam];
            f.showTitle = true;
            f.tid = true;
            f.valIdx = -1;
            f.valCap = vcap;
            f.valY = top;
            f.tidY = top + vcap + (lcap * 0.7 + 0.5).toNumber();
            var tidBottom = f.tidY + (lcap * 1.75 + 0.5).toNumber();   // 한글 윗선 기준 줄: 한글·괄호 아래 끝
            if (wantHist) {
                var ht = h / 2;
                if (tidBottom + vg > ht) { ht = tidBottom + vg; }
                f.histTop = ht;
            }
        } else if (bottom - top >= vcap) {
            f.showTitle = true;
            f.valIdx = -1;
            f.valCap = vcap;
            var vb = (bottom5 - top >= vcap) ? bottom5 : bottom;
            f.valY = top + (vb - top - vcap) / 2;
        } else {
            // 낮은 넓은 칸 (550/850 420x60 등): 타이틀 빼고 숫자만
            f.showTitle = false;
            var avail = bottom - T;
            var colW = wantSec ? (w - 2 * L - gap) / 2 : (w - 2 * L);
            f.valIdx = pick(colW, avail, 3.0);
            // 넓은 칸 값 크기를 넘지 않게 (Plus 시리즈와 같은 크기 유지)
            while (f.valIdx > 0 && CAP[f.valIdx] > vcap) { f.valIdx--; }
            f.valCap = CAP[f.valIdx];
            f.valY = T + (avail - f.valCap) / 2;
        }

        var mid = w / 2;
        f.xc1 = (L + mid - gap / 2) / 2;
        f.xc2 = (mid + gap / 2 + w - L) / 2;
        f.xcOne = mid;
        return f;
    }

    function min(a, b) { return (a < b) ? a : b; }
}
