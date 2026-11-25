using Toybox.Lang;
using Toybox.WatchUi;

// 운동 형태 판정 (Riduck "Animal Friends" 기준을 파워 존으로 옮긴 것).
// tools/ptype (판정기) 의 classify.js 와 같은 계산. 문턱값을 바꾸면 양쪽을 같이 맞춘다.
//
// 조건을 위에서부터(우선순위) 확인해 처음 맞는 형태를 고른다. 아무것도 안 맞으면 EASY.
// 스프린트·타바타·HIIT·VO2MAX 가 함께 맞으면 문턱을 가장 많이 넘긴 쪽.
// 넓고 높은 칸 + 설정 "운동 형태" 가 켜진 경우에만 10초마다 계산한다.
module PType {

    enum {
        POL, RACE, BALANCE, SPRINT, TABATA, HIIT, VO2MAX, SST, TEMPO, FATMAX, BASE, RECOVERY, EASY
    }
    const KEYS = [ "POL", "RACE", "BALANCE", "SPRINT", "TABATA", "HIIT", "VO2MAX",
                   "SST", "TEMPO", "FATMAX", "BASE", "RECOVERY", "EASY" ];

    const MIN = 60000;              // 1분 (ms)
    const MIN_MS = 10 * MIN;        // 기록 10분 미만이면 "분석 중"

    // 문턱값 (tools/ptype/classify.js DEFAULTS 와 같음). 시간은 분, 비율은 %
    const REC_MIN = 30;  const REC_Z1 = 70;  const REC_HI_MAX = 5;
    const BASE_MIN = 60; const BASE_LOW = 80; const BASE_Z2 = 40;
    const FAT_MIN = 120; const FAT_Z2 = 50;
    const TEMPO_Z3 = 60;
    const SST_MIN = 30;
    const VO2_Z5 = 20;
    const HIIT_Z6 = 10;
    const TAB_Z7 = 3;
    const SPR_NM = 1;
    const RACE_HI = 45;  const RACE_EACH = 5;
    const POL_MIN = 90;  const POL_LOW = 65; const POL_HI = 8; const POL_MID = 15;
    const BAL_EACH = 3;  const BAL_MAX = 35;

    var best = -1;                  // 형태 인덱스, 분석 전 -1
    var ready = false;
    var _names = null;

    function reset() {
        best = -1;
        ready = false;
    }

    // Zones.ms / ssMs / nmMs 로 다시 계산
    function update() {
        var total = Zones.total();
        ready = (total >= MIN_MS);
        if (!ready) {
            best = -1;
            return;
        }
        var z = Zones.ms;
        var pct = new [7];
        var mn = 100.0;
        var mx = 0.0;
        for (var i = 0; i < 7; i++) {
            pct[i] = z[i] * 100.0 / total;
            if (pct[i] < mn) { mn = pct[i]; }
            if (pct[i] > mx) { mx = pct[i]; }
        }
        var low = pct[0] + pct[1];
        var mid = pct[2] + pct[3];
        var hi = pct[4] + pct[5] + pct[6];
        var tMin = total / MIN.toFloat();
        var ss = Zones.ssMs;
        var nm = Zones.nmMs;

        // 우선순위 순서
        if (tMin >= POL_MIN && low >= POL_LOW && hi >= POL_HI && mid <= POL_MID) { best = POL; return; }
        var each = pct[3];
        for (var j = 4; j < 7; j++) { if (pct[j] < each) { each = pct[j]; } }
        if (pct[3] + hi >= RACE_HI && each >= RACE_EACH) { best = RACE; return; }
        if (mn >= BAL_EACH && mx <= BAL_MAX) { best = BALANCE; return; }

        // 고강도 4종: 문턱을 가장 많이 넘긴 쪽 (같으면 우선순위 위)
        var hiRatio = [
            nm.toFloat() / (SPR_NM * MIN),
            z[6].toFloat() / (TAB_Z7 * MIN),
            z[5].toFloat() / (HIIT_Z6 * MIN),
            z[4].toFloat() / (VO2_Z5 * MIN)
        ];
        var hb = -1;
        var hr = 1.0;
        for (var k = 0; k < 4; k++) {
            if (hiRatio[k] >= 1.0 && (hb < 0 || hiRatio[k] > hr)) {
                hb = k;
                hr = hiRatio[k];
            }
        }
        if (hb >= 0) { best = SPRINT + hb; return; }

        if (ss >= SST_MIN * MIN) { best = SST; return; }
        if (z[2] >= TEMPO_Z3 * MIN) { best = TEMPO; return; }
        if (tMin >= FAT_MIN && low >= BASE_LOW && pct[1] >= FAT_Z2) { best = FATMAX; return; }
        if (tMin >= BASE_MIN && low >= BASE_LOW && pct[1] >= BASE_Z2) { best = BASE; return; }
        if (tMin >= REC_MIN && pct[0] >= REC_Z1 && mid + hi <= REC_HI_MAX) { best = RECOVERY; return; }
        best = EASY;
    }

    // 형태 설명 (기기 언어: 한국어면 한글, 그 외 영문). 처음 쓸 때 한 번 읽는다.
    function name(i) {
        if (_names == null) {
            _names = [
                WatchUi.loadResource(Rez.Strings.ptPOL),
                WatchUi.loadResource(Rez.Strings.ptRACE),
                WatchUi.loadResource(Rez.Strings.ptBALANCE),
                WatchUi.loadResource(Rez.Strings.ptSPRINT),
                WatchUi.loadResource(Rez.Strings.ptTABATA),
                WatchUi.loadResource(Rez.Strings.ptHIIT),
                WatchUi.loadResource(Rez.Strings.ptVO2MAX),
                WatchUi.loadResource(Rez.Strings.ptSST),
                WatchUi.loadResource(Rez.Strings.ptTEMPO),
                WatchUi.loadResource(Rez.Strings.ptFATMAX),
                WatchUi.loadResource(Rez.Strings.ptBASE),
                WatchUi.loadResource(Rez.Strings.ptRECOVERY),
                WatchUi.loadResource(Rez.Strings.ptEASY)
            ];
        }
        return _names[i];
    }

    // "SST"
    function head() {
        return KEYS[best];
    }
}
