using Toybox.Lang;
using Toybox.Math;

// 파워 계산 (zzPowerChart 의 계산을 옮기고 고친 것). compute() 에서 1초에 한 번 add().
//  - 3초 / 10초 평균: 최근 10초 원형 버퍼
//  - NP : 30초 이동평균의 4제곱 평균의 4제곱근. 0W(페달 멈춤) 포함, 타이머 멈춤 동안은 제외
//  - 랩 평균: 랩 버튼마다 새로 시작 (가민과 같음). 타이머가 돌 때만, 0W 포함
//  - IF = NP / FTP, TSS = 시간(h) x IF² x 100
module Power {

    // 최근 10초 (3초·10초 평균). 타이머와 상관없이 매초 (멈춰 있을 때도 화면 값은 움직여야 해서)
    var buf10 = new [10];
    var idx10 = 0;
    var fill10 = 0;

    // NP
    var npBuf = new [30];
    var npIdx = 0;
    var npFill = 0;
    var npSum30 = 0;
    var np4Sum = 0.0d;
    var np4Cnt = 0;

    // 랩
    var lapSum = 0;
    var lapCnt = 0;

    // TSS 용 시간 (초, 타이머가 도는 동안)
    var secs = 0;

    function reset() {
        buf10 = new [10];
        idx10 = 0;
        fill10 = 0;
        npBuf = new [30];
        npIdx = 0;
        npFill = 0;
        npSum30 = 0;
        np4Sum = 0.0d;
        np4Cnt = 0;
        lapSum = 0;
        lapCnt = 0;
        secs = 0;
    }

    function lap() {
        lapSum = 0;
        lapCnt = 0;
    }

    // 1초 파워 넣기. running = 타이머가 도는 중
    function add(p, running) {
        if (p == null) { p = 0; }
        buf10[idx10] = p;
        idx10 = (idx10 + 1) % 10;
        if (fill10 < 10) { fill10++; }

        if (!running) {
            return;
        }
        secs++;
        lapSum += p;
        lapCnt++;

        if (npFill < 30) {
            npFill++;
        } else {
            npSum30 -= npBuf[npIdx];
        }
        npBuf[npIdx] = p;
        npSum30 += p;
        npIdx = (npIdx + 1) % 30;
        if (npFill >= 30) {
            var a = npSum30 / 30.0d;
            np4Sum += a * a * a * a;
            np4Cnt++;
        }
    }

    // 최근 n초 평균 (n <= 10). 아직 n초가 안 찼으면 있는 만큼
    function avgLast(n) {
        if (fill10 == 0) { return null; }
        if (n > fill10) { n = fill10; }
        var s = 0;
        for (var i = 1; i <= n; i++) {
            s += buf10[(idx10 - i + 10) % 10];
        }
        return s.toFloat() / n;
    }

    function np() {
        if (np4Cnt == 0) { return null; }
        return Math.pow(np4Sum / np4Cnt, 0.25).toFloat();
    }

    // 새 랩 첫 1초는 null (화면에서 현재 파워로 대신 보여줌)
    function lapAvg() {
        return (lapCnt > 0) ? lapSum.toFloat() / lapCnt : null;
    }

    function intensity(ftp) {
        var n = np();
        if (n == null || ftp == null || ftp <= 0) { return null; }
        return n / ftp;
    }

    function tss(ftp) {
        var f = intensity(ftp);
        if (f == null) { return null; }
        return secs / 3600.0 * f * f * 100.0;
    }
}
