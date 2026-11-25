using Toybox.Application.Properties;
using Toybox.Lang;

// 설정 스냅샷 + 캐싱. onUpdate 는 1Hz 이므로 매번 Properties 를 읽지 않고
// 캐시를 쓰고 onSettingsChanged 에서 invalidate() 한다.
// FTP·파워존 설정 키는 zzPowerChart 와 같은 이름을 쓴다.
module Config {

    // 배경색 (bgMode)
    enum {
        BG_AUTO  = 0,   // 기기 화면과 같은 색으로 칠함 (1050/1060 은 #17181D / 남색 글씨)
        BG_PLAIN = 1,   // 기기가 알려준 검정 / 흰색 그대로
        BG_CLEAR = 2    // 칠하지 않음 (기기 배경이 그대로 비침)
    }

    // 메인 값 (mainDataMode)
    enum {
        MAIN_1S  = 0,      // 순간 파워
        MAIN_3S  = 1,      // 3초 평균 (기본)
        MAIN_10S = 2       // 10초 평균
    }

    // 오른쪽 위 보조값 (dataMode)
    enum {
        SEC_AVG  = 0,
        SEC_MAX  = 1,
        SEC_LAP  = 2,
        SEC_NP   = 3,
        SEC_IF   = 4,
        SEC_TSS  = 5,
        SEC_NONE = 6
    }

    // 히스토그램 막대 모양
    enum {
        HIST_STRIPE = 0,   // 가로 줄무늬 (숫자가 잘 보임)
        HIST_SOLID  = 1    // 꽉 채움
    }

    // 색 테마 (colorHigh / colorLow) - Plus 시리즈와 같은 번호
    enum {
        COLOR_DEFAULT      = 0,
        COLOR_RED          = 1,
        COLOR_ORANGE       = 2,
        COLOR_YELLOW       = 3,
        COLOR_YELLOWORANGE = 4,
        COLOR_GREEN        = 5,
        COLOR_BLUE         = 6,
        COLOR_PURPLE       = 7,
        COLOR_PINK         = 8,
        COLOR_PINKRED      = 9,
        COLOR_GRAY         = 10,
        COLOR_ZONE         = 11
    }

    class Snapshot {
        var bgMode     = BG_PLAIN; // 배경색
        var main        = MAIN_3S;
        var secondary   = SEC_AVG;
        var showIcon    = true;     // 번개 + 존 번호
        var zoneDecimal = false;    // 존 번호 4.3 처럼 소수 한 자리 (기본: 정수, 큰 글씨)
        var showBar     = true;     // 하단 존 띠 + 현재 위치 화살표
        var showHist    = true;     // 존별 시간 % 막대
        var histStyle   = HIST_STRIPE;
        var showPct     = true;     // 막대 위 % 숫자
        var typeAnalysis = true;    // 넓고 높은 칸에서 운동 형태 화면

        // 파워존: 직접 입력 > FTP 계산 (Coggan / Stages)
        var ftp         = 200;
        var calcType    = 0;        // 0 Coggan, 1 Stages
        var manualZone  = false;
        var manualBounds = null;    // [Z1최대 .. Z6최대]

        // 색 테마: 보조값(평균 등) 대비 threshold% 이상 높으면 colorHigh, 낮으면 colorLow
        var threshold   = 5;
        var colorHigh   = COLOR_DEFAULT;
        var colorLow    = COLOR_DEFAULT;
    }

    var _cache = null;

    function invalidate() {
        _cache = null;
    }

    function _get(key, dflt) {
        try {
            var v = Properties.getValue(key);
            if (v != null) {
                return v;
            }
        } catch (ex) {
        }
        return dflt;
    }

    function _num(key, dflt, lo, hi) {
        var v = _get(key, dflt);
        if (v instanceof Lang.Float || v instanceof Lang.Double || v instanceof Lang.Long) {
            v = v.toNumber();
        }
        if (!(v instanceof Lang.Number)) {
            return dflt;
        }
        if (v < lo) { return lo; }
        if (v > hi) { return hi; }
        return v;
    }

    function _bool(key, dflt) {
        var v = _get(key, dflt);
        return (v instanceof Lang.Boolean) ? v : dflt;
    }

    function read() {
        if (_cache != null) {
            return _cache;
        }
        var s = new Snapshot();
        s.main        = _num("mainDataMode", MAIN_3S, 0, 2);
        s.secondary   = _num("dataMode", SEC_AVG, 0, 6);
        s.showIcon    = _bool("showIcon", true);
        s.zoneDecimal = _bool("zoneDecimal", false);
        s.showBar     = _bool("powerZoneBar", true);
        s.showHist    = _bool("powerZoneHistory", true);
        s.histStyle   = _num("histStyle", HIST_STRIPE, 0, 1);
        s.showPct     = _bool("showPct", true);
        s.typeAnalysis = _bool("typeAnalysis", true);

        s.ftp         = _num("FTP", 200, 50, 600);
        s.calcType    = _num("calcTypePZ", 0, 0, 1);
        s.manualZone  = _bool("manualPowerZone", false);
        if (s.manualZone) {
            s.manualBounds = [
                _num("Zone1maxValue", 110, 10, 3000),
                _num("Zone2maxValue", 150, 10, 3000),
                _num("Zone3maxValue", 180, 10, 3000),
                _num("Zone4maxValue", 210, 10, 3000),
                _num("Zone5maxValue", 240, 10, 3000),
                _num("Zone6maxValue", 300, 10, 3000)
            ];
        }

        s.threshold   = _num("threshold", 5, 0, 100);
        s.colorHigh   = _num("colorHigh", COLOR_DEFAULT, 0, 11);
        s.colorLow    = _num("colorLow", COLOR_DEFAULT, 0, 11);
        s.bgMode      = _num("bgMode", BG_PLAIN, 0, 2);
        _cache = s;
        return s;
    }
}
