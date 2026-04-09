# mono-test.js — Headless CLI Test Runner

LLM이 브라우저 없이 로컬에서 직접 게임을 실행하고 `vdump()`로 화면 상태를 텍스트로 검증하는 도구.

## 목적

로컬 LLM이 코드 수정 → 실행 → 검증 루프를 사람 개입 없이 자동으로 돌리기 위함.

## 사용법

```bash
node mono-test.js main.lua --frames 30
# → _init() → _start() → _update()×30 → _draw() → vdump 출력
# → 에러 시 에러 메시지 + exit code 1
```

## LLM 자동 루프

```
1. main.lua 수정
2. node mono-test.js main.lua --frames 5
3. 출력 확인 (vdump 텍스트 or 에러)
4. 수정 반복
```

## 핵심 구조

- **Wasmoon**: npm 패키지 (`wasmoon@1.16.0`)로 Node.js에서 Lua 실행
- **렌더링**: `colorBuf = new Uint8Array(160*144)`에 실제 그리기 — Canvas/DOM 없이 `setPix`, `cls`, `rect`, `text` 등 그대로 동작
- **buf32 대체**: `palette[]` 룩업 스킵하거나 더미 `Uint32Array`로 대체
- **vdump()**: `colorBuf`에서 hex 텍스트 출력 — LLM이 화면 상태 검증
- **loadImage**: Node.js `fs.readFile` + `sharp` 또는 순수 PNG 디코더로 대체 (`createImageBitmap` 없음)

## 구현 시 주의점

- `engine.js`의 드로잉 함수들을 공유하거나 복제해야 함 (`colorBuf`에 쓰는 로직)
- font 데이터도 포함 필요 (`text` 함수 동작용)
- input (`btn`/`btnp`)은 스텁 또는 시나리오 주입 방식
- 이미지 로딩은 Node.js `fs` + 이미지 디코더 필요 (브라우저 API 없음)
- 엔진 코드 이중화를 피하려면 드로잉 코어를 모듈로 분리하는 것이 이상적

## 출력 예시

```
$ node mono-test.js main.lua --frames 1

_init OK
_start OK
Frame 1: _update OK, _draw OK

--- vdump ---
0000000000000000000000000000...
0000000000000000000000000000...
000000000000ffff00000000000...
000000000000f00f00000000000...
...

OK (1 frame, no errors)
```

## Input Replay

실제 플레이 또는 입력 시퀀스를 파일로 기록하고 나중에 재생하여 결정론적 회귀 테스트를 만들 수 있다.

### 기록

```bash
node mono-test.js game.lua --frames 100 --input "5:right,10:a,20:up" --record session.replay
# → session.replay 파일에 프레임별 입력 기록
```

### 재생

```bash
node mono-test.js game.lua --frames 100 --replay session.replay --snapshot actual.txt
# → 동일한 입력 시퀀스로 실행 → VRAM 스냅샷 비교 가능
```

### Replay 파일 포맷

```
# mono replay v1
# seed=42 colors=1 frames=100
5 right
10 a
20 up
```

- 한 줄 = 한 프레임 (입력이 있는 프레임만)
- `frame keys...` — 해당 프레임에 활성화된 키들 (공백 구분)
- `#` 으로 시작하는 줄은 주석/메타데이터
- 메타데이터의 `seed=N`은 `--seed` 미지정 시 자동 적용

### 사용 시나리오

- **버그 리포트**: 버그 재현 시나리오를 `.replay` 파일로 저장 → 엔진 수정 후 동일한 replay로 회귀 테스트
- **AI 루프**: AI가 생성한 코드가 기존 replay를 통과하는지 자동 검증
- **데모 녹화**: 특정 게임 플레이 흐름을 기록해 두고 데모로 활용

## Visual Diff (`--diff`)

`--snapshot`으로 저장한 vdump 파일과 현재 실행 결과를 비교한다. 불일치 시 차이나는 픽셀 개수와 퍼센티지를 표시하고, 4:1 다운스케일 ASCII 아트로 expected / actual / diff map을 side-by-side로 출력한다.

```bash
# 1. 기대 출력 저장
node mono-test.js game.lua --frames 30 --snapshot expected.txt

# 2. 엔진 수정 후 동일 상태 검증
node mono-test.js game.lua --frames 30 --diff expected.txt
```

### 출력 예시 (불일치)

```
DIFF: MISMATCH ✗
  1511 pixels differ (6.56%)
  First diff at row 2:
  expected: 30ffff0f00f00fff...
  actual:   30ffff0f00f00fff...

  expected              actual              diff
  --------              --------            ----
  :-:--:-: --::-        :-:--:-: --::-      .........X.XXXXXX
  ---+:-+. :-:::        ---+:-+. :-:::      .........XXXXXXXX
  ...                   ...                  ...
```

- **diff map**: `X` = 해당 블록 내 최소 1픽셀 차이, `.` = 완전 일치
- 엔진 변경이 어디에 영향을 줬는지 눈으로 바로 파악 가능
- AI가 실패 원인을 이해하기 쉬움 (텍스트 비교만으로는 불가능)

## Determinism Verification (`--determinism`)

같은 seed로 N번 실행하여 모든 실행의 VRAM이 동일한지 (FNV-1a 해시 비교) 검증한다. Lockstep 멀티플레이어의 전제 조건인 결정론적 실행을 보장하기 위함.

```bash
node mono-test.js game.lua --frames 120 --determinism 5 --seed 42
```

### 출력 예시 (통과)

```
=== DETERMINISM CHECK ===
Runs:   5
Seed:   42
Frames: 120
Unique VRAM hashes: 1
DETERMINISM: PASS ✓  (all runs produced hash af0d75fb)
```

### 출력 예시 (실패)

```
=== DETERMINISM CHECK ===
Runs:   5
Seed:   42
Frames: 120
Unique VRAM hashes: 3
DETERMINISM: FAIL ✗  (3 distinct hashes)
  af0d75fb: 2 runs
  1c3a8e9b: 2 runs
  7f2d9c01: 1 runs

Lockstep multiplayer requires deterministic execution.
Common causes: unseeded math.random(), table iteration order,
time-based APIs, uninitialized state.
```

### 비결정론의 흔한 원인

- `math.random()` 시드 미설정
- Lua 테이블 순회 순서 (insertion order 보장 안 됨)
- `os.time()`, `os.clock()` 같은 시간 기반 API
- 전역 상태 초기화 누락

## API Coverage (`--coverage`)

실행 중 어떤 엔진 API가 호출되었는지 추적하여 사용/미사용 API를 리포트한다. 데드 API 제거 후보를 찾는 데 유용.

```bash
node mono-test.js game.lua --frames 30 --coverage --quiet
```

### 출력 예시

```
=== API COVERAGE ===
Total APIs:  52
Used:        14 (26.9%)
Unused:      38

Used APIs (by call count):
  pix     480 calls
  text     91 calls
  rect     60 calls
  cls      31 calls
  ...

Unused APIs:
  gpix, note, tone, noise, wave, sfx_stop, cam_shake, ...
```

### 활용

- **데드 API 감지**: 아무 데모도 사용 안 하는 API는 제거 후보 (ALPHA 단계에서 적극 권장)
- **커버리지 검증**: 새 데모가 엔진 API를 충분히 테스트하는지 확인
- **LLM 호출 패턴**: AI가 생성한 코드가 실제로 어떤 API를 쓰는지 분석

## Gameplay Trace (`--trace`)

각 프레임의 상태(VRAM 해시, 활성 입력, 새로 출력된 로그)를 JSONL 형식으로 저장한다. AI가 게임 플레이를 분석하거나 버그 리포트를 자동화하는 데 활용.

```bash
node mono-test.js game.lua --frames 100 --input "5:right,20:a" --trace session.jsonl
```

### JSONL 포맷

```json
{"frame":1,"hash":"1b2ae874","keys":[],"logs":[]}
{"frame":2,"hash":"65a4c22a","keys":["right"],"logs":[]}
{"frame":3,"hash":"442a724a","keys":[],"logs":["[Lua] score=10"]}
```

각 줄 = 한 프레임:
- `frame`: 프레임 번호
- `hash`: VRAM FNV-1a 32-bit 해시
- `keys`: 해당 프레임에 활성화된 키 배열
- `logs`: 해당 프레임에서 새로 출력된 Lua print 문

### 활용

- **AI 플레이 분석**: LLM에게 trace를 전달 → "왜 프레임 50에서 게임이 멈췄는지 분석해줘"
- **자동 버그 리포트**: 버그 발생 시 trace 파일을 함께 제출
- **회귀 테스트**: 해시 시퀀스가 예상과 다르면 엔진이 바뀐 지점을 프레임 단위로 특정 가능
- **AI Self-Play**: `_bot()` 시스템과 결합해 AI가 스스로 플레이하고 결과를 분석

## 향후 확장

- `.mono/CONTEXT.md`에 mono-test 사용법 자동 포함
