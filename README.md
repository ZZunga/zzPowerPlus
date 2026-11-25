# zzPowerPlus (zz파워+)

Garmin Edge 파워 데이터 필드. 화면 배치는 zzHeartPlus 와 같고, 파워 계산은 zzPowerChart 를 옮겨 고친 것.

대상: Edge 540 / 550 / 840 / 850 / 1040 / 1050 / 1060

## 화면
- 좁은 칸: 번개 + 파워존(기본 정수, 큰 글씨) / 오른쪽 위 보조값, 아래 큰 메인 파워, 배경에 존별 시간 히스토그램과 7존 띠
- 넓은 칸: 타이틀 줄(번개 + 존 + zzPowerPlus + 라벨), 메인 파워와 보조값 나란히
- 넓고 높은 칸: 값 아래 운동 형태 한 줄 (`SST - 스윗스팟`), 아래쪽 절반 히스토그램(% 숫자)
- 1000W 이상은 kW: 좁은 칸 `1` + `.25` + 2단 `k`/`W`, 넓은 칸 `1.25`

## 계산 (source/Power.mc)
- 메인: 순간 / 3초 평균(기본) / 10초 평균
- 보조: 평균, 최대, 랩 평균, NP, IF, TSS, 없음
- NP: 30초 이동평균의 4제곱 평균의 4제곱근. 0W 포함, 타이머가 멈춘 동안은 제외, 정지 후에도 이어서 계산
- 랩 평균: 랩 버튼마다 새로 시작, 타이머가 도는 동안만, 0W 포함. 새 랩 첫 1초는 현재 파워
- IF = NP / FTP, TSS = 시간(h) x IF² x 100

## 파워존 (source/Zones.mc)
- FTP 설정값으로 계산: Coggan 55/75/90/105/120/150%, Stages 59/79/90/104/120/150%
- 직접 입력(각 존 최대 W)을 켜면 그 값 사용
- 존별 시간은 1초 파워 기준, 타이머가 도는 동안만. 스윗스팟(FTP 88~95%)과 200% 이상 시간도 따로 셈

## 운동 형태 (source/PType.mc)
- tools/ptype/index.html (판정기) 와 같은 규칙. 기록 10분 미만이면 "분석 중"
- POL, RACE, BALANCE, SPRINT, TABATA, HIIT, VO2MAX, SST, TEMPO, FATMAX, BASE, RECOVERY, EASY
- 문턱값을 바꾸면 PType.mc 상수와 classify.js DEFAULTS 를 같이 맞춘다

## 폰트 다시 만들기
- 숫자·라벨·단위: `java tools/FntGen.java <ttf> <outDir> <base> <chars> - <px...>`
- 운동 형태 줄(한글 포함): `python tools/TidFont.py <outDir> <cap>` (HANGUL 에 형태 이름 글자)
- C10Sub 의 '@' 는 power.svg 번개 (폭 = 숫자 높이, 높이 = 폭/0.875)
- 미리보기: `python tools/preview.py` → tools/preview.png
