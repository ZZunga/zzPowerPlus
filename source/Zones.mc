using Toybox.Application.Storage;
using Toybox.Lang;

// 파워존 계산 + 존별 누적 시간.
//
// 경계값 6개 = [Z1 최대, Z2 최대, Z3 최대, Z4 최대, Z5 최대, Z6 최대] (W). Z7 은 Z6 최대 초과.
// 존 번호는 가민 기기와 같은 소수 표기: Z4 구간의 30% 지점이면 4.3.
// 운동 형태 판정용으로 스윗스팟(FTP 88~95%)과 200% 이상 시간도 따로 센다 (존 시간에도 포함).
module Zones {

    const N = 7;
    const STORE_KEY = "pz";

    // FTP 기준 비율 (calcTypePZ, zzPowerChart 와 같은 값)
    //  0 Coggan  55 / 75 / 90 / 105 / 120 / 150 %
    //  1 Stages  59 / 79 / 90 / 104 / 120 / 150 %
    const CALC = [
        [0.55, 0.75, 0.90, 1.05, 1.20, 1.50],
        [0.59, 0.79, 0.90, 1.04, 1.20, 1.50]
    ];

    var bounds = null;                      // 6개 경계값 or null
    var ssLo = 176;                         // 스윗스팟 하한 (FTP 88%)
    var ssHi = 190;                         // 스윗스팟 상한 (FTP 95%)
    var nmLo = 400;                         // 200% 이상
    var ms = [0, 0, 0, 0, 0, 0, 0];         // 존별 누적 시간 (ms, 타이머가 도는 동안만)
    var ssMs = 0;
    var nmMs = 0;

    // 존 경계 읽기: 직접 입력 > FTP 계산
    function loadBounds() {
        var cfg = Config.read();
        var ftp = cfg.ftp;
        ssLo = (ftp * 0.88).toNumber();
        ssHi = (ftp * 0.95).toNumber();
        nmLo = ftp * 2;
        bounds = null;
        if (cfg.manualZone && valid(cfg.manualBounds)) {
            bounds = cfg.manualBounds;
            return;
        }
        var pct = CALC[cfg.calcType];
        var b = new [6];
        for (var i = 0; i < 6; i++) {
            b[i] = (ftp * pct[i]).toNumber();
        }
        if (valid(b)) {
            bounds = b;
        }
    }

    // 6개, 모두 양수, 오름차순일 때만 사용
    function valid(b) {
        if (b == null || !(b instanceof Lang.Array) || b.size() < 6) {
            return false;
        }
        for (var i = 0; i < 6; i++) {
            if (b[i] == null || b[i] <= 0) {
                return false;
            }
            if (i > 0 && b[i] <= b[i - 1]) {
                return false;
            }
        }
        return true;
    }

    // 소수 존 (예: 4.3). 파워 없으면 null. 0W 는 1.0
    function zoneOf(p) {
        if (p == null) {
            return null;
        }
        if (bounds == null) {
            loadBounds();
            if (bounds == null) {
                return null;
            }
        }
        var b = bounds;
        if (p <= b[0]) {
            var f0 = p.toFloat() / b[0];
            if (f0 > 0.99) { f0 = 0.99; }
            return 1.0 + f0;
        }
        for (var i = 1; i < 6; i++) {
            if (p <= b[i]) {
                var lo = b[i - 1];
                var span = b[i] - lo;
                var frac = (span > 0) ? (p - lo).toFloat() / span : 0.0;
                if (frac > 0.99) { frac = 0.99; }
                return (i + 1) + frac;
            }
        }
        // Z7: Z6 최대의 2배를 끝으로 봄
        var f7 = (p - b[5]).toFloat() / b[5];
        if (f7 > 0.99) { f7 = 0.99; }
        if (f7 < 0.0) { f7 = 0.0; }
        return 7.0 + f7;
    }

    // 소수 존 -> 히스토그램 칸 0..6 (Z1..Z7)
    function bucketOf(zone) {
        if (zone == null) {
            return -1;
        }
        var i = zone.toNumber() - 1;
        if (i < 0) { i = 0; }
        if (i > N - 1) { i = N - 1; }
        return i;
    }

    // 1초 파워 p 로 deltaMs 만큼 누적
    function add(p, zone, deltaMs) {
        var bucket = bucketOf(zone);
        if (bucket >= 0 && bucket < N) {
            ms[bucket] += deltaMs;
        }
        if (p >= ssLo && p <= ssHi) {
            ssMs += deltaMs;
        }
        if (p >= nmLo) {
            nmMs += deltaMs;
        }
    }

    function total() {
        var t = 0;
        for (var i = 0; i < N; i++) {
            t += ms[i];
        }
        return t;
    }

    // 존별 비율 0.0 ~ 1.0
    function ratio(i) {
        var t = total();
        return (t > 0) ? ms[i].toFloat() / t : 0.0;
    }

    function reset() {
        ms = [0, 0, 0, 0, 0, 0, 0];
        ssMs = 0;
        nmMs = 0;
        try {
            Storage.deleteValue(STORE_KEY);
        } catch (ex) {
        }
    }

    // 앱이 중간에 다시 켜져도(프로필 전환 등) 누적값을 잃지 않게 저장.
    // [타이머 ms, z1..z7 ms, 스윗스팟 ms, 200%↑ ms]
    function save(timerMs) {
        try {
            Storage.setValue(STORE_KEY, [timerMs, ms[0], ms[1], ms[2], ms[3], ms[4], ms[5], ms[6], ssMs, nmMs]);
        } catch (ex) {
        }
    }

    // 지금 타이머 시각과 맞는 저장값이면 복원. 저장된 타이머가 지금보다 크면
    // 이전 라이딩 값이므로 버린다. 복원했으면 저장된 타이머 ms, 아니면 null.
    function restore(timerMs) {
        try {
            var v = Storage.getValue(STORE_KEY);
            if (v instanceof Lang.Array && v.size() == 10 && v[0] != null
                    && v[0] > 0 && v[0] <= timerMs + 2000) {
                ms = [v[1], v[2], v[3], v[4], v[5], v[6], v[7]];
                ssMs = v[8];
                nmMs = v[9];
                return v[0];
            }
        } catch (ex) {
        }
        return null;
    }
}
