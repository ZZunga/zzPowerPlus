using Toybox.Activity;
using Toybox.FitContributor;
using Toybox.Graphics;
using Toybox.System;
using Toybox.WatchUi;

// zzPowerPlus 데이터 필드.
//   현재 파워(1초/3초/10초) + 파워존 + 존별 시간 비율 히스토그램 + 운동 형태.
// 화면 배치는 zzHeartPlus 와 같고, 파워 계산은 zzPowerChart 를 옮긴 Power 모듈.
// 레이아웃 XML 없이 코드로 그린다.
class zzPowerPlusView extends WatchUi.DataField {

    hidden var mFrame = null;
    hidden var mFontCache;
    hidden var mUnitCache;
    hidden var mWideVal = null;     // 넓은 칸 폰트 (넓은 칸일 때만 로드)
    hidden var mWideTitle = null;
    hidden var mWideLabel = null;
    hidden var mTidFont = null;     // 운동 형태 줄 (운동 형태 화면일 때만 로드)
    hidden var mMainF = null;       // 좁은 칸: 메인 숫자 / 메인 단위 / 보조값·존 / 보조 단위
    hidden var mUnitF = null;
    hidden var mSubF = null;
    hidden var mZoneF = null;       // 존 번호 중간 크기 폰트 (좁은 칸) / 큰 폰트 (넓은 칸)
    hidden var mTinyF = null;       // 존 번호 가장 작은 폰트 (좁은 칸)
    hidden var mBg = Graphics.COLOR_WHITE;   // 번개 테두리(배경색) 용
    hidden var mSubUnitF = null;

    hidden var mCur = null;      // 1초 파워
    hidden var mPow = null;      // 메인 값 (설정: 1초 / 3초 / 10초)
    hidden var mZone = null;     // 메인 값의 소수 존 (4.3)
    hidden var mAvg = null;
    hidden var mMax = null;

    hidden var mLastTimer = null;   // 직전 compute 의 info.timerTime (ms)
    hidden var mRestored = false;
    hidden var mTick = 0;

    // FIT 기록: 레코드마다 현재 존, 세션 요약에 존별 비율(%)
    hidden var mFitZone = null;
    hidden var mFitPct = null;

    // 번개 모양 (power.svg, Font Awesome Free 6.6 solid bolt). 448 x 512 기준. 둥근 모서리는 꼭짓점으로 단순화.
    const BOLT = [
        [349, 45], [339, 6], [299, 8], [43, 232], [34, 267], [64, 288], [176, 288],
        [99, 467], [109, 506], [149, 504], [405, 280], [414, 245], [384, 224], [272, 224]
    ];

    function initialize() {
        DataField.initialize();
        mFontCache = new [Layout.NFONTS];
        mUnitCache = new [Layout.NFONTS];
        Zones.loadBounds();

        try {
            mFitZone = createField("pwr_zone", 0, FitContributor.DATA_TYPE_FLOAT,
                { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "zone" });
            mFitPct = new [Zones.N];
            for (var i = 0; i < Zones.N; i++) {
                mFitPct[i] = createField("z" + (i + 1) + "_pct", i + 1, FitContributor.DATA_TYPE_UINT8,
                    { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%" });
            }
        } catch (ex) {
            mFitZone = null;
            mFitPct = null;
        }
    }

    function onSettingsChanged() {
        mFrame = null;
        Zones.loadBounds();     // 존 출처/값이 바뀌었을 수 있음
    }

    // ---- 데이터 (1Hz) ------------------------------------------------

    function compute(info) {
        mTick++;
        var cfg = Config.read();

        mCur = (info has :currentPower) ? info.currentPower : null;
        mAvg = (info has :averagePower) ? info.averagePower : null;
        mMax = (info has :maxPower) ? info.maxPower : null;

        var running = true;
        if (info has :timerState) {
            running = (info.timerState == Activity.TIMER_STATE_ON);
        }

        // 3초·10초 평균, NP, 랩, TSS (1초에 한 번)
        if (mCur != null) {
            Power.add(mCur, running);
        }
        if (mCur == null) {
            mPow = null;
        } else if (cfg.main == Config.MAIN_3S) {
            mPow = Power.avgLast(3);
        } else if (cfg.main == Config.MAIN_10S) {
            mPow = Power.avgLast(10);
        } else {
            mPow = mCur;
        }
        mZone = Zones.zoneOf(mPow);

        // 존별 시간: 타이머 시간이 늘어난 만큼 1초 파워의 존에 더한다
        // (자동 일시정지 동안은 timerTime 이 멈추므로 자연히 빠진다)
        var t = (info has :timerTime) ? info.timerTime : null;
        if (t != null) {
            // 앱이 활동 중간에 다시 켜졌을 때만 저장값 복원 (첫 compute 에서 한 번)
            if (!mRestored) {
                mRestored = true;
                if (t > 0) {
                    var saved = Zones.restore(t);
                    if (saved != null) {
                        mLastTimer = saved;
                    }
                }
            }
            if (mLastTimer != null && t < mLastTimer) {
                Zones.reset();          // 새 활동
                Power.reset();
                mLastTimer = null;
            }
            if (mLastTimer != null) {
                var d = t - mLastTimer;
                if (running && mCur != null && d > 0 && d < 5000) {
                    Zones.add(mCur, Zones.zoneOf(mCur), d);
                }
            }
            mLastTimer = t;
        }

        // FIT
        if (mFitZone != null && running && mZone != null) {
            mFitZone.setData(mZone);
        }
        if (mTick % 10 == 0) {
            updateFitSession();
        }
        if (mTick % 60 == 0 && t != null) {
            Zones.save(t);
        }

        // 운동 형태: 넓고 높은 칸 + 설정 켬일 때만, 10초마다 (처음 한 번은 바로)
        if (mFrame != null && mFrame.tid && (mTick % 10 == 0 || (!PType.ready && Zones.total() >= PType.MIN_MS))) {
            PType.update();
        }
    }

    hidden function updateFitSession() {
        if (mFitPct == null || Zones.total() <= 0) {
            return;
        }
        for (var i = 0; i < Zones.N; i++) {
            mFitPct[i].setData((Zones.ratio(i) * 100 + 0.5).toNumber());
        }
    }

    function persist() {
        if (mLastTimer != null) {
            Zones.save(mLastTimer);
        }
    }

    function onTimerStart() {
        Zones.loadBounds();     // 스포츠 프로필별 존이 바뀌었을 수 있음
    }

    function onTimerPause() {
        persist();
    }

    function onTimerStop() {
        updateFitSession();
        persist();
    }

    function onTimerLap() {
        Power.lap();
    }

    function onTimerReset() {
        Zones.reset();
        Power.reset();
        PType.reset();
        mLastTimer = null;
        mCur = null;
        mPow = null;
        mZone = null;
        mAvg = null;
        mMax = null;
    }

    // ---- 폰트 -------------------------------------------------------

    hidden function loadFont(idx) {
        switch (idx) {
            case 0:  return WatchUi.loadResource(Rez.Fonts.Num18);
            case 1:  return WatchUi.loadResource(Rez.Fonts.Num24);
            case 2:  return WatchUi.loadResource(Rez.Fonts.Num30);
            case 3:  return WatchUi.loadResource(Rez.Fonts.Num38);
            case 4:  return WatchUi.loadResource(Rez.Fonts.Num48);
            case 5:  return WatchUi.loadResource(Rez.Fonts.Num60);
            case 6:  return WatchUi.loadResource(Rez.Fonts.Num76);
            case 7:  return WatchUi.loadResource(Rez.Fonts.Num96);
            case 8:  return WatchUi.loadResource(Rez.Fonts.Num120);
            case 9:  return WatchUi.loadResource(Rez.Fonts.Num150);
            default: return WatchUi.loadResource(Rez.Fonts.Num190);
        }
    }

    hidden function font(idx) {
        if (idx < 0 || idx >= Layout.NFONTS) {
            return null;
        }
        if (mFontCache[idx] == null) {
            mFontCache[idx] = loadFont(idx);
        }
        return mFontCache[idx];
    }

    // 칸 폭이 화면 폭의 75% 를 넘으면 넓은 칸 (zzSpeedPlus / zzCadencePlus 와 같은 판정)
    hidden function makeFrame(dc) {
        var cfg = Config.read();
        var w = dc.getWidth();
        var h = dc.getHeight();
        var screenW = System.getDeviceSettings().screenWidth;
        var hasSec = (cfg.secondary != Config.SEC_NONE);
        // 칸이 바뀌면 안 쓰는 폰트는 내려놓는다 (메모리)
        mFontCache = new [Layout.NFONTS];
        mUnitCache = new [Layout.NFONTS];
        mWideVal = null;
        mWideTitle = null;
        mWideLabel = null;
        mTidFont = null;
        mMainF = null;
        mUnitF = null;
        mSubF = null;
        mZoneF = null;
        mTinyF = null;
        mSubUnitF = null;
        if (w > screenW * 0.75) {
            mFrame = Layout.computeWide(w, h, screenW, hasSec,
                cfg.showBar || cfg.showHist, cfg.showHist && cfg.showPct, cfg.typeAnalysis, cfg.showIcon);
            if (mFrame.showTitle) {
                mWideVal   = WatchUi.loadResource(Rez.Fonts.WideVal);
                mWideTitle = WatchUi.loadResource(Rez.Fonts.WideTitle);
                mWideLabel = WatchUi.loadResource(Rez.Fonts.WideLabel);
                if (mFrame.bigZone) {
                    mZoneF = WatchUi.loadResource(Rez.Fonts.C10Sub);   // 존 번호 크게
                }
            }
            if (mFrame.tid) {
                // 메모리: TID 폰트(글리프 수백 자)와 % 숫자 폰트를 함께 올리면
                // 넓은 칸에서 한도를 넘어 폰트 로드가 실패한다. TID 줄을 쓰면 % 숫자는 생략.
                mFrame.pctIdx = -1;
                mTidFont = WatchUi.loadResource(Rez.Fonts.TidLabel);
                PType.update();
            } else if (mFrame.pctIdx >= 0) {
                font(mFrame.pctIdx);   // 그리는 도중 로드하지 않도록 미리 올려둔다
            }
        } else {
            mFrame = Layout.compute(w, h, screenW, cfg.showIcon, hasSec,
                cfg.showBar || cfg.showHist, cfg.zoneDecimal);
            var f = mFrame;
            if (f.c10) {
                mMainF = WatchUi.loadResource(Rez.Fonts.C10Main);
                mUnitF = WatchUi.loadResource(Rez.Fonts.C10UnitMain);
                if (f.secIdx >= 0 || f.zoneIdx >= 0 || f.iconSize > 0) {
                    mSubF = WatchUi.loadResource(Rez.Fonts.C10Sub);       // 번개('@' 글리프)·kW 소수도 이 폰트
                }
                if (f.secIdx >= 0) {
                    mSubUnitF = WatchUi.loadResource(Rez.Fonts.C10UnitSub);
                }
            } else {
                mMainF = font(f.mainIdx);
                mUnitF = unitFont(f.unitIdx);
                if (f.zoneIdx >= 0) {
                    mSubF = font(f.zoneIdx);
                }
                if (f.secIdx >= 0) {
                    mSubF = font(f.secIdx);
                    mSubUnitF = unitFont(f.secLabelIdx);
                }
            }
            if (f.zoneIdx >= 0) {
                mZoneF = (f.zoneNum >= 0) ? font(f.zoneNum) : null;    // 중간 크기
                mTinyF = WatchUi.loadResource(Rez.Fonts.NumTiny);       // 가장 작은 크기
            }
        }
    }

    function onLayout(dc) {
        makeFrame(dc);
    }

    // ---- 그리기 ----------------------------------------------------

    function onUpdate(dc) {
        var cfg = Config.read();
        if (mFrame == null || mFrame.w != dc.getWidth() || mFrame.h != dc.getHeight()) {
            makeFrame(dc);
        }
        var f = mFrame;

        // 배경색 (설정 bgMode)
        //   0 자동 : 1050/1060 은 기기 화면과 같은 색으로 칠한다 (#17181D / 남색 글씨)
        //   1 그대로 : 기기가 알려준 검정·흰색 그대로 칠한다
        //   2 투명 : 아예 칠하지 않아 기기 배경이 그대로 비친다 (테마가 무엇이든 일치)
        var bg = getBackgroundColor();
        var sysClear = (bg == Graphics.COLOR_TRANSPARENT);   // 기기가 "투명"이라고 알려준 경우
        var dark = (bg == Graphics.COLOR_BLACK || sysClear);
        var big = (System.getDeviceSettings().screenWidth >= 480);
        var soft = big && (cfg.bgMode != Config.BG_PLAIN);
        var fg;
        if (dark) {
            bg = soft ? 0x17181D : Graphics.COLOR_BLACK;
            fg = Graphics.COLOR_WHITE;
        } else {
            bg = soft ? 0xDCDCDC : Graphics.COLOR_WHITE;   // 1050/1060 의 밝은 배경은 순백이 아니다
            fg = soft ? 0x313152 : Graphics.COLOR_BLACK;
        }
        var dim = dark ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_DK_GRAY;
        var boltColor = dark ? Graphics.COLOR_YELLOW : Graphics.COLOR_ORANGE;   // 번개 색

        mBg = bg;
        // 지우기만 투명으로 (mBg 는 도형 속을 파낼 때 쓰므로 실제 색 유지).
        // 자동 모드에서도 기기가 투명이라고 알려줬으면 칠하지 않는다 - 그게 색이 어긋나던 원인.
        var noFill = (cfg.bgMode == Config.BG_CLEAR)
                  || (cfg.bgMode == Config.BG_AUTO && sysClear);
        var clearBg = noFill ? Graphics.COLOR_TRANSPARENT : bg;
        dc.setColor(clearBg, clearBg);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        var bucket = Zones.bucketOf(mZone);

        if (f.wide) {
            drawWide(dc, f, cfg, dark, bucket, fg, dim, boltColor);
            return;
        }

        // ---- 좁은 칸 ----
        // 배경 히스토그램 + 하단 존 띠 (좁은 칸은 % 숫자 없음)
        if (f.stripH > 0) {
            drawHistogram(dc, f, cfg, dark, bucket, [], dim, fg);
        }

        // 번개 + 존 번호 (보조값과 같은 크기)
        if (f.iconSize > 0) {
            if (f.c10 && mSubF != null) {
                drawBoltGlyph(dc, f.iconX, f.iconY, f.iconSize, f.zoneTop, f.subCap, mSubF, boltColor);
            } else {
                drawBolt(dc, f.iconX, f.iconY, f.iconSize, boltColor);
            }
            if (f.zoneIdx >= 0) {
                // 존 번호: 보조값 왼쪽 끝까지 들어가는 가장 큰 글씨 (보조값 폰트 → 중간 → 가장 작은)
                var right = f.w - f.inset;
                if (f.secIdx >= 0 && mSubF != null) {
                    right = f.secRightX - dc.getTextWidthInPixels(secStr(cfg.secondary), mSubF);
                }
                var room = right - 2 - f.zoneX + 1;           // +1: 글자 폭 끝의 자간 1px
                var zs = zoneStr(f.zoneDec);
                var zf = null;
                var zcap = 0;
                if (mSubF != null && dc.getTextWidthInPixels(zs, mSubF) <= room) {
                    zf = mSubF; zcap = f.subCap;
                } else if (mZoneF != null && dc.getTextWidthInPixels(zs, mZoneF) <= room) {
                    zf = mZoneF; zcap = Layout.CAP[f.zoneNum];
                } else if (mTinyF != null && dc.getTextWidthInPixels(zs, mTinyF) <= room) {
                    zf = mTinyF; zcap = Layout.TINY_CAP;
                }
                if (zf != null) {
                    dc.setColor((mZone != null && mZone >= 1.0) ? zoneColor(bucket, dark) : dim, Graphics.COLOR_TRANSPARENT);
                    dc.drawText(f.zoneX, f.zoneTop + f.subCap - zcap, zf, zs, Graphics.TEXT_JUSTIFY_LEFT);
                }
            }
        }

        // 오른쪽 위 보조값 + 단위 (IF·TSS 는 단위 없음)
        if (f.secIdx >= 0) {
            var sv = secValue(cfg.secondary);
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(f.secRightX, f.secTop, mSubF, secStr(cfg.secondary), Graphics.TEXT_JUSTIFY_RIGHT);
            if (secIsPower(cfg.secondary)) {
                drawUnit(dc, f.w - f.inset, f.secTop, f.secLabelTop, mSubUnitF, f.subUnitCap, fg, sv != null && sv >= 999.5);
            }
        }

        // 메인 파워 (오른쪽 아래) + 단위. 색 테마 적용.
        //  1000W 이상: 큰 정수 + 작은 소수 두 자리(보조값 글씨, 바닥선 맞춤) + 2단 "k"/"W"
        dc.setColor(mainColor(cfg, dark, fg, bucket), Graphics.COLOR_TRANSPARENT);
        var kw = (mPow != null && mPow >= 999.5);
        if (kw && f.c10 && mSubF != null) {
            var n = ((mPow + 5) / 10).toNumber();                 // 0.01 kW 단위
            var dec = "." + (n % 100).format("%02d");
            var decW = dc.getTextWidthInPixels(dec, mSubF);
            dc.drawText(f.mainX, f.mainBase - f.subCap, mSubF, dec, Graphics.TEXT_JUSTIFY_RIGHT);
            dc.drawText(f.mainX - decW, f.mainTop, mMainF, (n / 100).toString(), Graphics.TEXT_JUSTIFY_RIGHT);
        } else {
            dc.drawText(f.mainX, f.mainTop, mMainF, fmtPow(mPow), Graphics.TEXT_JUSTIFY_RIGHT);
        }
        drawUnit(dc, f.w - f.inset, f.mainTop, f.mainBase, mUnitF, f.unitCap, fg, kw);
    }

    // 단위: "W" 는 숫자 윗선(top)에 맞춰 오른쪽 정렬.
    //  kW 이면 2단: 윗줄 "k", 아랫줄 "W" (심박앱 "bp"/"m" 과 같은 간격, 숫자 바닥선은 넘지 않음)
    hidden function drawUnit(dc, right, top, base, uFont, uCap, color, kw) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (!kw) {
            dc.drawText(right, top, uFont, "W", Graphics.TEXT_JUSTIFY_RIGHT);
            return;
        }
        dc.drawText(right, top, uFont, "k", Graphics.TEXT_JUSTIFY_RIGHT);
        var y2 = top + (uCap * 1.6 + 0.5).toNumber();
        if (y2 > base - uCap) { y2 = base - uCap; }
        dc.drawText(right, y2, uFont, "W", Graphics.TEXT_JUSTIFY_RIGHT);
    }

    hidden function unitFont(idx) {
        if (mUnitCache[idx] == null) {
            var r;
            switch (idx) {
                case 0:
                case 1:  r = Rez.Fonts.Unit9;  break;
                case 2:  r = Rez.Fonts.Unit12; break;
                case 3:  r = Rez.Fonts.Unit14; break;
                case 4:  r = Rez.Fonts.Unit19; break;
                case 5:  r = Rez.Fonts.Unit23; break;
                case 6:  r = Rez.Fonts.Unit29; break;
                case 7:  r = Rez.Fonts.Unit38; break;
                case 8:  r = Rez.Fonts.Unit47; break;
                case 9:  r = Rez.Fonts.Unit59; break;
                default: r = Rez.Fonts.Unit75;
            }
            mUnitCache[idx] = WatchUi.loadResource(r);
        }
        return mUnitCache[idx];
    }

    // 존별 시간 비율 막대. 막대 높이 = 비율 x 사용 가능 높이 (100% 면 칸 위까지).
    hidden function drawHistogram(dc, f, cfg, dark, cur, blocks, dim, fg) {
        var w = f.w;
        var base = f.histBase;
        var avail = base - f.histTop;
        var total = Zones.total();
        var pctFont = (f.pctIdx >= 0) ? font(f.pctIdx) : null;

        for (var i = 0; i < Zones.N; i++) {
            var x0 = (w * i) / Zones.N;
            var x1 = (w * (i + 1)) / Zones.N;
            var color = zoneColor(i, dark);

            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            if (cfg.showBar) {
                dc.fillRectangle(x0, base, x1 - x0 - 1, f.stripH);
            }

            if (!cfg.showHist || total <= 0) {
                continue;
            }
            var r = Zones.ratio(i);
            var bh = (avail * r).toNumber();
            var bx = x0 + 1;
            var bw = x1 - x0 - 2;
            var top = base - bh;
            if (bh > 0) {
                if (cfg.histStyle == Config.HIST_SOLID) {
                    dc.setColor(barSolid(i, dark), Graphics.COLOR_TRANSPARENT);
                    dc.fillRectangle(bx, top, bw, bh);
                } else {
                    dc.setPenWidth(1);
                    for (var y = base - 2; y >= top; y -= f.hatchStep) {
                        dc.drawLine(bx, y, bx + bw, y);
                    }
                    dc.drawLine(bx, top, bx + bw, top);   // 막대 윗선
                }
            }

            // % 라벨: 막대 바로 위. 메인 숫자와 겹치면 생략.
            if (pctFont != null && r > 0) {
                var label = (r * 100 + 0.5).toNumber().toString() + "%";
                var capH = Layout.CAP[f.pctIdx];
                var ly = top - capH - 2;
                if (ly < f.histTop) {
                    ly = top + 2;                       // 꽉 찬 막대는 안쪽으로
                }
                var cx = (x0 + x1) / 2;
                var lw = dc.getTextWidthInPixels(label, pctFont);
                var lx0 = cx - lw / 2;
                var lx1 = cx + lw / 2;
                var hit = false;
                for (var k = 0; k < blocks.size(); k++) {
                    var b = blocks[k];
                    if (lx0 < b[2] && lx1 > b[0] && ly < b[3] && ly + capH > b[1]) {
                        hit = true;
                        break;
                    }
                }
                if (!hit) {
                    dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
                    dc.drawText(cx, ly, pctFont, label, Graphics.TEXT_JUSTIFY_CENTER);
                }
            }
        }

        // 현재 파워 위치 화살표 (존 바 화살표). 존 안의 소수 위치까지 반영.
        if (cfg.showBar && mZone != null) {
            var a = f.stripH + 2;
            var pos = mZone - 1.0;
            if (pos < 0.0) { pos = 0.0; }
            var cxp = (w * pos / Zones.N).toNumber();
            if (cxp < a) { cxp = a; }
            if (cxp > w - a) { cxp = w - a; }
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[cxp - a, base - a], [cxp, base], [cxp + a, base - a]]);
        }
    }

    // ---- 넓은 칸 ----------------------------------------------------------
    //  [⚡ 4 zzPowerPlus                  AVG W]
    //  [     245          |       198         ]   두 값 같은 크기 (보조값 없음이면 가운데 하나)
    hidden function drawWide(dc, f, cfg, dark, bucket, fg, dim, boltColor) {
        var hasSec = (cfg.secondary != Config.SEC_NONE);
        var vFont = (f.valIdx < 0) ? mWideVal : font(f.valIdx);
        var hrStr = fmtPow(mPow);
        var sStr = hasSec ? secStr(cfg.secondary) : null;

        // % 라벨이 피할 사각형: 타이틀 줄 + 값 두 개
        var blocks = [];
        if (f.showTitle) {
            blocks.add([0, 0, f.w, f.zoneY + f.tlineH]);
        }
        var x1 = hasSec ? f.xc1 : f.xcOne;
        var w1 = dc.getTextWidthInPixels(hrStr, vFont);
        blocks.add([x1 - w1 / 2 - 2, f.valY - 2, x1 + w1 / 2 + 2, f.valY + f.valCap + 2]);
        if (hasSec) {
            var w2 = dc.getTextWidthInPixels(sStr, vFont);
            blocks.add([f.xc2 - w2 / 2 - 2, f.valY - 2, f.xc2 + w2 / 2 + 2, f.valY + f.valCap + 2]);
        }
        if (f.tid) {
            blocks.add([0, f.tidY - 2, f.w, f.histTop]);   // 운동 형태 줄은 히스토그램 위쪽
        }
        if (f.stripH > 0) {
            drawHistogram(dc, f, cfg, dark, bucket, blocks, dim, fg);
        }

        // 타이틀 줄: 번개 + 존 번호(존 색) + 앱 이름 / 오른쪽 회색 라벨
        if (f.showTitle) {
            var tcap = Layout.WIDE_TCAP[f.fam];
            var x = f.inset;
            if (cfg.showIcon) {
                if (f.bigZone && mZoneF != null) {
                    drawBoltGlyph(dc, x, f.heartY, f.heartSize, f.zoneY, Layout.C10_SCAP[f.fam], mZoneF, boltColor);
                } else {
                    drawBolt(dc, x, f.heartY, f.heartSize, boltColor);
                }
                x += f.heartSize + (tcap * 0.3).toNumber();
                var zs = zoneStr(cfg.zoneDecimal);
                var zf = (f.bigZone && mZoneF != null) ? mZoneF : mWideTitle;
                dc.setColor((mZone != null && mZone >= 1.0) ? zoneColor(bucket, dark) : dim, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, f.zoneY, zf, zs, Graphics.TEXT_JUSTIFY_LEFT);
                x += dc.getTextWidthInPixels(zs, zf) + (tcap * 0.5).toNumber();
            }
            var label = secLabelWide(cfg.secondary);
            var lw = dc.getTextWidthInPixels(label, mWideLabel);
            var title = f.shortTitle ? "zzPower+" : "zzPowerPlus";
            if (!f.shortTitle && x + dc.getTextWidthInPixels(title, mWideTitle) > f.titleRight - lw - 4) {
                title = "zzPower+";                       // 존 번호가 커서 긴 이름이 안 들어가면 짧은 이름
            }
            if (x + dc.getTextWidthInPixels(title, mWideTitle) <= f.titleRight - lw - 4) {
                dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, f.titleY, mWideTitle, title, Graphics.TEXT_JUSTIFY_LEFT);
            }
            dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
            dc.drawText(f.titleRight, f.labelY, mWideLabel, label, Graphics.TEXT_JUSTIFY_RIGHT);
        }

        // 값: 현재 파워(색 테마) | 보조값. 같은 폰트, 같은 크기. 1000W 이상은 "1.25" (kW)
        dc.setColor(mainColor(cfg, dark, fg, bucket), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x1, f.valY, vFont, hrStr, Graphics.TEXT_JUSTIFY_CENTER);
        if (hasSec) {
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(f.xc2, f.valY, vFont, sStr, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // 운동 형태: 파워 바로 아래 한 줄, 파워 숫자 왼쪽 끝에 맞춤. "SST - 스윗스팟"
        if (f.tid && mTidFont != null) {
            var right = f.w - f.inset;
            var lx = x1 - w1 / 2;
            var ty = f.tidY - Layout.TID_PAD[f.fam];       // 폰트 위쪽 여유만큼 올려 그림 (글자 윗선 = tidY)
            if (!PType.ready || PType.best < 0) {
                dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
                dc.drawText(lx, ty, mTidFont, WatchUi.loadResource(Rez.Strings.ptAnalyzing), Graphics.TEXT_JUSTIFY_LEFT);
            } else {
                var head = PType.head();
                var tail = " - " + PType.name(PType.best);
                var hw = dc.getTextWidthInPixels(head, mTidFont);
                var tw = dc.getTextWidthInPixels(tail, mTidFont);
                if (lx + hw + tw > right) {
                    lx = f.inset;                          // 길면 칸 왼쪽 여백부터
                }
                dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
                dc.drawText(lx, ty, mTidFont, head, Graphics.TEXT_JUSTIFY_LEFT);
                if (lx + hw + tw <= right) {               // 그래도 길면 이름은 생략
                    dc.setColor(dim, Graphics.COLOR_TRANSPARENT);
                    dc.drawText(lx + hw, ty, mTidFont, tail, Graphics.TEXT_JUSTIFY_LEFT);
                }
            }
        }
    }

    hidden function secLabelWide(kind) {
        if (kind == Config.SEC_AVG) { return "AVG W"; }
        if (kind == Config.SEC_MAX) { return "MAX W"; }
        if (kind == Config.SEC_LAP) { return "LAP W"; }
        if (kind == Config.SEC_NP)  { return "NP W"; }
        if (kind == Config.SEC_IF)  { return "IF"; }
        if (kind == Config.SEC_TSS) { return "TSS"; }
        return "W";
    }

    // 메인 숫자 색. 높음/낮음 색이 기본이면 글자색.
    // 보조값(평균/최대/랩평균/NP, 그 외는 평균) 대비 threshold% 넘게 높으면 colorHigh, 낮으면 colorLow.
    // 둘 중 하나라도 "파워존 색"이면 항상 현재 존 색.
    hidden function mainColor(cfg, dark, fg, bucket) {
        if (cfg.colorHigh == Config.COLOR_ZONE || cfg.colorLow == Config.COLOR_ZONE) {
            return (mZone != null && mZone >= 1.0) ? zoneColor(bucket, dark) : fg;
        }
        if (mPow == null || (cfg.colorHigh == Config.COLOR_DEFAULT && cfg.colorLow == Config.COLOR_DEFAULT)) {
            return fg;
        }
        var ref = secIsPower(cfg.secondary) ? secValue(cfg.secondary) : mAvg;
        if (ref == null || ref <= 0) {
            return fg;
        }
        var d = ref * cfg.threshold / 100.0;
        var sel = Config.COLOR_DEFAULT;
        if (mPow > ref + d) {
            sel = cfg.colorHigh;
        } else if (mPow < ref - d) {
            sel = cfg.colorLow;
        }
        var c = themeColor(sel, dark);
        return (c != null) ? c : fg;
    }

    // zzPowerChart getColor() 와 같은 색 (검정 배경용, 흰 배경용)
    hidden function themeColor(sel, dark) {
        switch (sel) {
            case Config.COLOR_RED:          return dark ? Graphics.COLOR_RED : Graphics.COLOR_DK_RED;
            case Config.COLOR_ORANGE:       return Graphics.COLOR_ORANGE;
            case Config.COLOR_YELLOW:       return Graphics.COLOR_YELLOW;
            case Config.COLOR_YELLOWORANGE: return dark ? Graphics.COLOR_YELLOW : Graphics.COLOR_ORANGE;
            case Config.COLOR_GREEN:        return dark ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GREEN;
            case Config.COLOR_BLUE:         return dark ? Graphics.COLOR_BLUE : Graphics.COLOR_DK_BLUE;
            case Config.COLOR_PURPLE:       return Graphics.COLOR_PURPLE;
            case Config.COLOR_PINK:         return Graphics.COLOR_PINK;
            case Config.COLOR_PINKRED:      return dark ? Graphics.COLOR_PINK : Graphics.COLOR_DK_RED;
            case Config.COLOR_GRAY:         return dark ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_DK_GRAY;
            default:                        return null;
        }
    }

    // ---- helpers -------------------------------------------------

    // 존 색 (7존): 회색 / 파랑 / 초록 / 노랑 / 주황 / 빨강 / 보라
    hidden function zoneColor(i, dark) {
        switch (i) {
            case 0:  return dark ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_DK_GRAY;
            case 1:  return dark ? Graphics.COLOR_BLUE    : Graphics.COLOR_DK_BLUE;
            case 2:  return dark ? Graphics.COLOR_GREEN   : Graphics.COLOR_DK_GREEN;
            case 3:  return Graphics.COLOR_YELLOW;
            case 4:  return Graphics.COLOR_ORANGE;
            case 5:  return dark ? Graphics.COLOR_RED     : Graphics.COLOR_DK_RED;
            default: return dark ? Graphics.COLOR_PINK    : Graphics.COLOR_PURPLE;
        }
    }

    // 채움 막대는 숫자가 보이도록 옅은 색
    hidden function barSolid(i, dark) {
        switch (i) {
            case 0:  return dark ? 0x333333 : 0xDDDDDD;
            case 1:  return dark ? 0x0A2A40 : 0xD0D0FF;
            case 2:  return dark ? 0x0A3A0A : 0xCCEECC;
            case 3:  return dark ? 0x40380A : 0xFFEECC;
            case 4:  return dark ? 0x40250A : 0xFFDCCC;
            case 5:  return dark ? 0x4D0A0A : 0xEECCCC;
            default: return dark ? 0x3A0A40 : 0xEED0FF;
        }
    }

    hidden function zoneStr(decimal) {
        if (mZone == null) {
            return "-";
        }
        if (decimal) {
            // 반올림하면 2.99 가 "3.0" 이 되므로 버림
            var tenth = (mZone * 10).toNumber();
            return (tenth / 10).toString() + "." + (tenth % 10).toString();
        }
        var z = mZone.toNumber();
        return (z < 1) ? "1" : z.toString();
    }

    hidden function fmt(v) {
        if (v == null) {
            return "--";
        }
        return (v + 0.5).toNumber().toString();
    }

    // 파워 문자열: 999W 까지 정수, 1000W 이상은 kW 소수 두 자리 ("1.25")
    hidden function fmtPow(v) {
        if (v == null) {
            return "--";
        }
        if (v >= 999.5) {
            var n = ((v + 5) / 10).toNumber();
            return (n / 100).toString() + "." + (n % 100).format("%02d");
        }
        return (v + 0.5).toNumber().toString();
    }

    hidden function secIsPower(kind) {
        return kind == Config.SEC_AVG || kind == Config.SEC_MAX || kind == Config.SEC_LAP || kind == Config.SEC_NP;
    }

    hidden function secValue(kind) {
        var cfg = Config.read();
        if (kind == Config.SEC_AVG) { return mAvg; }
        if (kind == Config.SEC_MAX) { return mMax; }
        if (kind == Config.SEC_LAP) {
            var l = Power.lapAvg();
            return (l != null) ? l : mCur;                  // 새 랩 첫 1초는 0 대신 현재 파워
        }
        if (kind == Config.SEC_NP)  { return Power.np(); }
        if (kind == Config.SEC_IF)  { return Power.intensity(cfg.ftp); }
        if (kind == Config.SEC_TSS) { return Power.tss(cfg.ftp); }
        return null;
    }

    hidden function secStr(kind) {
        var v = secValue(kind);
        if (kind == Config.SEC_IF) {
            return (v == null) ? "--" : v.format("%.2f");
        }
        if (kind == Config.SEC_TSS) {
            return fmt(v);
        }
        return fmtPow(v);
    }

    // 번개 상자 높이 = 폭 / 0.875. 배경색 테두리(히스토그램 줄무늬 위에서 가장자리가 뭉개지지 않게)를 먼저 그리고 그 위에 번개
    hidden function drawBolt(dc, x, y, s, color) {
        var h = (s / 12).toNumber();
        if (h < 1) { h = 1; }
        fillBolt(dc, x - h, y - h, s + 2 * h, mBg);
        fillBolt(dc, x, y, s, color);
    }

    // C10Sub 폰트의 '@' = power.svg 를 미리 안티앨리어싱한 번개 (높이 = 숫자 높이의 1.14배).
    //  배경색 테두리는 다각형으로 먼저 깔고(줄무늬 위), 글리프 가운데 = 숫자 가운데
    hidden function drawBoltGlyph(dc, x, y, s, top, cap, font, color) {
        var h = (s / 12).toNumber();
        if (h < 1) { h = 1; }
        fillBolt(dc, x - h, y - h, s + 2 * h, mBg);
        var gh = (s / Layout.BOLT_AR + 0.5).toNumber();   // 글리프 높이
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, top + cap / 2 - gh / 2, font, "@", Graphics.TEXT_JUSTIFY_LEFT);
    }

    hidden function fillBolt(dc, x, y, s, color) {
        var n = BOLT.size();
        var pts = new [n];
        var k = s / 448.0;
        for (var i = 0; i < n; i++) {
            pts[i] = [x + BOLT[i][0] * k, y + BOLT[i][1] * k];
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
    }
}
