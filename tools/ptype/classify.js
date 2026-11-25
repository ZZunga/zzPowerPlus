// zzPowerPlus 운동 형태 판정기: 파워 존별 시간 → 운동 형태 (Riduck "Animal Friends" 기준을 파워로 옮김).
//
// 입력 (분):
//   z[0..6] = Z1..Z7 시간 (FTP 기준 7존: Z1 ≤55%, Z2 56-75, Z3 76-90, Z4 91-105, Z5 106-120, Z6 121-150, Z7 >150)
//   ss      = 스윗스팟 88~95% 시간 (Z3·Z4 에 걸침, 따로 셈)
//   nm      = 200% 이상 시간 (Z7 안, 따로 셈)
//
// 방식: 각 형태의 조건을 확인하고, 조건을 다 채운 형태 중 우선순위가 가장 높은 것을 고른다.
//   아무것도 안 맞으면 EASY(일상 라이딩). 기록이 짧으면 "분석 중".
//   충족도(0~100%)는 조건에 얼마나 가까운지 보여주는 참고값 (화면 순위용).
// 기기(Monkey C)에는 문턱값 정수 몇 개와 if 문으로 그대로 옮긴다.

const DEFAULTS = {
  minMinutes: 10,      // 이보다 짧으면 "분석 중"
  // 회복 (거북이)
  recMin: 30,  recZ1: 70,  recHiMax: 5,          // 30분 이상, Z1 ≥70%, Z3 이상 ≤5%
  // 베이스 (소) / FATMAX (낙타)
  baseMin: 60, baseLow: 80, baseZ2: 40,          // 60분 이상, Z1+Z2 ≥80%, Z2 ≥40%
  fatMin: 120, fatZ2: 50,                        // 120분 이상, Z2 ≥50% (나머지는 베이스 조건)
  // 템포 (돼지) / SST (멧돼지)
  tempoZ3: 60,                                   // Z3 60분 이상
  sstMin: 30,                                    // 88~95% 30분 이상
  // 고강도
  vo2Z5: 20,                                     // Z5 20분 이상 (늑대)
  hiitZ6: 10,                                    // Z6 10분 이상 (표범)
  tabZ7: 3,                                      // Z7 3분 이상 (호랑이)
  sprNm: 1,                                      // 200%↑ 1분 이상 (사자)
  raceHi: 45, raceEach: 5,                       // Z4~Z7 합 ≥45%, Z4·Z5·Z6·Z7 각각 ≥5% (여러 강도를 섞음, 말)
  // 양극화 (코끼리)
  polMin: 90, polLow: 65, polHi: 8, polMid: 15,  // 90분 이상, Z1+Z2 ≥65%, Z5 이상 ≥8%, Z3+Z4 ≤15%
  // 밸런스 (개)
  balEach: 3, balMax: 35                         // Z1~Z7 모두 ≥3%, 어느 존도 35% 넘지 않음
};

// 우선순위 순서 (위가 먼저). 동물 이름은 참고용, 기기에는 표시하지 않음.
// 자유 라이딩(개)은 Z1~Z7 이 모두 있어야 해서 인터벌 훈련과는 겹치지 않는다. 고강도 몇 분이 섞인 그룹 라이딩을 타바타 등으로 보지 않도록 고강도 단일 형태보다 앞.
const TYPES = [
  { key: "POL",      ko: "양극화",          animal: "코끼리", desc: "저강도 위주에 고강도를 섞고 중간 강도는 거의 없음" },
  { key: "RACE",     ko: "레이스 페이스",     animal: "말",    desc: "Z4~Z7 고강도가 여러 번 섞인 경기형 라이딩" },
  { key: "BALANCE",  ko: "자유 라이딩",       animal: "개",    desc: "Z1~Z7 여러 강도를 골고루" },
  { key: "SPRINT",   ko: "스프린트",         animal: "사자",   desc: "FTP 200% 이상 순간 최대 파워" },
  { key: "TABATA",   ko: "타바타",          animal: "호랑이", desc: "Z7(150%↑) 아주 짧고 강한 반복" },
  { key: "HIIT",     ko: "짧은 고강도 인터벌", animal: "표범",   desc: "Z6(121~150%) 짧은 인터벌" },
  { key: "VO2MAX",   ko: "최대산소 인터벌",   animal: "늑대",   desc: "Z5(106~120%) 긴 인터벌로 심폐 능력 향상" },
  { key: "SST",      ko: "스윗스팟",         animal: "멧돼지", desc: "FTP 88~95% 지속, 효율적인 지구력·파워" },
  { key: "TEMPO",    ko: "템포",            animal: "돼지",   desc: "Z3(76~90%) 1시간 이상 꾸준히" },
  { key: "FATMAX",   ko: "장거리 지방 연소",   animal: "낙타",   desc: "Z2 위주 2시간 이상 (LSD)" },
  { key: "BASE",     ko: "베이스",           animal: "소",    desc: "Z1~Z2 저강도 1~2시간, 유산소 기초" },
  { key: "RECOVERY", ko: "회복 라이딩",       animal: "거북이", desc: "Z1(55% 미만) 가볍게 30분 이상" },
  { key: "EASY",     ko: "일상 라이딩",       animal: "오리",   desc: "특별한 목표 없는 가벼운 라이딩 (다른 조건에 안 맞을 때)" }
];

const clamp01 = x => Math.max(0, Math.min(1, x));
// 여러 조건의 충족도: 각 조건 0~1 의 최솟값
const all = (...xs) => Math.min(...xs.map(clamp01));
const atLeast = (v, t) => (t <= 0 ? 1 : v / t);
const atMost = (v, t) => (v <= t ? 1 : t / v);

function stats(inp) {
  const z = inp.z.map(v => Math.max(0, +v || 0));
  const total = z.reduce((a, b) => a + b, 0);
  const pct = z.map(v => (total > 0 ? v / total * 100 : 0));
  const low = pct[0] + pct[1], mid = pct[2] + pct[3], hi = pct[4] + pct[5] + pct[6];
  const ss = Math.min(Math.max(0, +inp.ss || 0), z[2] + z[3]);
  const nm = Math.min(Math.max(0, +inp.nm || 0), z[6]);
  return { z, total, pct, low, mid, hi, ss, nm };
}

// 형태별 [충족도 0~1, 설명 문자열]
function check(s, t) {
  const { z, total, pct, low, mid, hi, ss, nm } = s;
  const r = {};
  r.POL = [all(atLeast(total, t.polMin), atLeast(low, t.polLow), atLeast(hi, t.polHi), atMost(mid, t.polMid)),
    `${total}분 ≥${t.polMin} · 저강도 ${low.toFixed(0)}% ≥${t.polLow} · 고강도 ${hi.toFixed(0)}% ≥${t.polHi} · 중강도 ${mid.toFixed(0)}% ≤${t.polMid}`];
  const each = Math.min(pct[3], pct[4], pct[5], pct[6]);
  r.RACE = [all(atLeast(pct[3] + hi, t.raceHi), atLeast(each, t.raceEach)),
    `Z4~Z7 ${(pct[3] + hi).toFixed(0)}% ≥${t.raceHi} · Z4~Z7 중 가장 적은 존 ${each.toFixed(0)}% ≥${t.raceEach}`];
  r.SPRINT = [all(atLeast(nm, t.sprNm)), `200%↑ ${nm.toFixed(1)}분 ≥${t.sprNm}`];
  r.TABATA = [all(atLeast(z[6], t.tabZ7)), `Z7 ${z[6]}분 ≥${t.tabZ7}`];
  r.HIIT = [all(atLeast(z[5], t.hiitZ6)), `Z6 ${z[5]}분 ≥${t.hiitZ6}`];
  r.VO2MAX = [all(atLeast(z[4], t.vo2Z5)), `Z5 ${z[4]}분 ≥${t.vo2Z5}`];
  r.SST = [all(atLeast(ss, t.sstMin)), `88~95% ${ss}분 ≥${t.sstMin}`];
  r.TEMPO = [all(atLeast(z[2], t.tempoZ3)), `Z3 ${z[2]}분 ≥${t.tempoZ3}`];
  r.FATMAX = [all(atLeast(total, t.fatMin), atLeast(low, t.baseLow), atLeast(pct[1], t.fatZ2)),
    `${total}분 ≥${t.fatMin} · Z1+Z2 ${low.toFixed(0)}% ≥${t.baseLow} · Z2 ${pct[1].toFixed(0)}% ≥${t.fatZ2}`];
  r.BASE = [all(atLeast(total, t.baseMin), atLeast(low, t.baseLow), atLeast(pct[1], t.baseZ2)),
    `${total}분 ≥${t.baseMin} · Z1+Z2 ${low.toFixed(0)}% ≥${t.baseLow} · Z2 ${pct[1].toFixed(0)}% ≥${t.baseZ2}`];
  r.RECOVERY = [all(atLeast(total, t.recMin), atLeast(pct[0], t.recZ1), atMost(mid + hi, t.recHiMax)),
    `${total}분 ≥${t.recMin} · Z1 ${pct[0].toFixed(0)}% ≥${t.recZ1} · Z3 이상 ${(mid + hi).toFixed(0)}% ≤${t.recHiMax}`];
  const minEach = Math.min(...pct), maxEach = Math.max(...pct);
  r.BALANCE = [all(atLeast(minEach, t.balEach), atMost(maxEach, t.balMax)),
    `가장 적은 존 ${minEach.toFixed(0)}% ≥${t.balEach} · 가장 많은 존 ${maxEach.toFixed(0)}% ≤${t.balMax}`];
  r.EASY = [1, "다른 조건에 안 맞으면"];
  return r;
}

function classify(inp, t = DEFAULTS) {
  const s = stats(inp);
  const res = check(s, t);
  const list = TYPES.map((ty, i) => ({ ...ty, prio: i, fit: res[ty.key][0], why: res[ty.key][1], ok: res[ty.key][0] >= 1 }));
  const ready = s.total >= t.minMinutes && s.total > 0;
  let best = list.find(x => x.ok);
  // 고강도 4종(스프린트·타바타·HIIT·VO2MAX)이 함께 맞으면 문턱을 가장 많이 넘긴 쪽
  // (예: 30/30 인터벌은 Z7 도 몇 분 쌓이지만 Z6 이 주인공)
  const HI = { SPRINT: s.nm / t.sprNm, TABATA: s.z[6] / t.tabZ7, HIIT: s.z[5] / t.hiitZ6, VO2MAX: s.z[4] / t.vo2Z5 };
  if (best && best.key in HI) {
    best = list.filter(x => x.ok && x.key in HI).sort((a, b) => HI[b.key] - HI[a.key] || a.prio - b.prio)[0];
  }
  const also = list.filter(x => x.ok && x !== best && x.key !== "EASY");
  return { ...s, ready, best, also, list };
}

// 대표 라이딩 (존별 분 Z1..Z7, 88~95% 분, 200%↑ 분). expect 는 사람이 보기에 그럴듯한 답.
const PRESETS = [
  { name: "회복 45분",            z: [35, 9, 1, 0, 0, 0, 0],      ss: 0,  nm: 0,   expect: "RECOVERY" },
  { name: "베이스 90분",           z: [20, 65, 5, 0, 0, 0, 0],     ss: 0,  nm: 0,   expect: "BASE" },
  { name: "LSD 3시간",            z: [40, 125, 12, 3, 0, 0, 0],   ss: 2,  nm: 0,   expect: "FATMAX" },
  { name: "템포 90분",            z: [10, 15, 62, 3, 0, 0, 0],    ss: 10, nm: 0,   expect: "TEMPO" },
  { name: "스윗스팟 2x20분",       z: [15, 25, 20, 25, 0, 0, 0],   ss: 40, nm: 0,   expect: "SST" },
  { name: "VO2max 5x5분",         z: [15, 25, 4, 4, 25, 2, 0],    ss: 2,  nm: 0,   expect: "VO2MAX" },
  { name: "30/30 HIIT",          z: [20, 15, 0, 3, 5, 14, 3],    ss: 0,  nm: 0.5, expect: "HIIT" },
  { name: "타바타",               z: [20, 10, 0, 0, 0, 3, 6],     ss: 0,  nm: 0.5, expect: "TABATA" },
  { name: "스프린트 훈련",          z: [30, 20, 0, 0, 0, 0, 3],     ss: 0,  nm: 2,   expect: "SPRINT" },
  { name: "크리테리움 60분",        z: [8, 8, 8, 12, 12, 8, 4],     ss: 6,  nm: 1.5, expect: "RACE" },
  { name: "Z2 2.5시간 + 5x4분",    z: [40, 80, 3, 3, 20, 0, 0],    ss: 1,  nm: 0,   expect: "POL" },
  { name: "동네 그룹 라이딩",        z: [15, 15, 12, 10, 6, 4, 3],   ss: 4,  nm: 0.2, expect: "BALANCE" },
  { name: "출퇴근 25분",           z: [12, 8, 3, 2, 0, 0, 0],      ss: 1,  nm: 0,   expect: "EASY" },
  { name: "막 출발 6분",           z: [3, 3, 0, 0, 0, 0, 0],       ss: 0,  nm: 0,   expect: "-" }
];

if (typeof module !== "undefined") {
  module.exports = { DEFAULTS, TYPES, PRESETS, classify, stats };
}
