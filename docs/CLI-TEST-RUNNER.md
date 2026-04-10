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
node mono-test.js main.lua --frames 100 --input "5:right,10:a,20:up" --record session.replay
# → session.replay 파일에 프레임별 입력 기록
```

### 재생

```bash
node mono-test.js main.lua --frames 100 --replay session.replay --snapshot actual.txt
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

## Diff (`--diff`)

`--snapshot`으로 저장한 vdump 파일과 현재 실행 결과를 비교한다. 불일치 시 차이나는 픽셀 개수/퍼센티지 + 최대 10개의 differing row를 hex 형태로 출력한다.

```bash
# 1. 기대 출력 저장
node mono-test.js main.lua --frames 30 --snapshot expected.txt

# 2. 엔진 수정 후 동일 상태 검증
node mono-test.js main.lua --frames 30 --diff expected.txt
```

### 출력 예시 (불일치)

```
DIFF: MISMATCH ✗
  1515 pixels differ (6.58%)
  differing rows: 46 total (showing first 10)
    row  16  exp: 3000cccccccccccccccccccccccccccccc00008888888888888888...
              act: 300000000000000000000000000000000000000000000000000000...
    row  17  exp: 3000c0000000000000000000000000000c00008888888888888888...
              act: 300000000000000000000000000000000000000000000000000000...
    ...
    ... 36 more differing rows
```

각 행은 그대로 hex이므로 `0` = 픽셀 없음, `f` = 최대 밝기로 읽힌다. 더 자세히 보려면 같은 프레임을 `--vdump` + `--region X,Y,W,H`로 다시 실행해서 관심 영역만 확대한다.

## Determinism Verification (`--determinism`)

같은 seed로 N번 실행하여 모든 실행의 VRAM이 동일한지 (FNV-1a 해시 비교) 검증한다. Lockstep 멀티플레이어의 전제 조건인 결정론적 실행을 보장하기 위함.

```bash
node mono-test.js main.lua --frames 120 --determinism 5 --seed 42
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

### 단일 게임

```bash
node mono-test.js main.lua --frames 30 --coverage --quiet
```

**주의**: 단일 게임 커버리지는 해당 게임이 사용하는 API만 보여준다. 엔진 전체의 API 사용 현황을 보려면 **`--scan`과 함께 사용**해 여러 게임의 커버리지를 합산해야 한다.

### 여러 게임 합산 (권장)

```bash
node mono-test.js --scan ./demo --frames 30 --coverage --quiet
```

### 출력 예시 (aggregated)

```
=== AGGREGATED COVERAGE (2 games) ===
Public APIs: 41
Used:        13 (31.7%)
Unused:      28

Used APIs (by total call count):
  rectf    751 calls   [engine-test, shader-test]
  pix      480 calls   [engine-test]
  text     121 calls   [engine-test, shader-test]
  ...

Unused APIs (dead code candidates):
  gpix, note, tone, noise, wave, sfx_stop, cam_shake, ...
```

- 각 API 옆 `[게임1, 게임2]`는 어느 게임이 사용했는지 표시
- 내부 API (`_` 접두사, 예: `_btn`, `_cam_get_x`)는 Lua 글루 코드용이라 자동 필터링

### 활용

- **데드 API 감지**: 어떤 데모도 사용하지 않는 API는 제거 후보 (ALPHA 단계에서 적극 권장)
- **카테고리 커버리지 확인**: 오디오(note/tone/noise), 터치, 스프라이트 등이 미사용이면 **해당 카테고리를 테스트하는 데모가 없다는 신호**
- **LLM 호출 패턴**: AI가 생성한 코드가 실제로 어떤 API를 쓰는지 분석

### GAMMA 단계 확장: 퍼블리싱된 게임 전체 커버리지

퍼블리싱 시스템이 생기면 `--scan`은 `monogame-storage/release/users/**` 전체에 돌릴 수 있지만, 실행이 느려진다. 대신 **퍼블리싱 시 정적 분석**으로 각 게임이 어떤 API를 쓰는지 기록해두는 게 효율적.

```
  Developer publishes ──► Firebase Function
                              │
                              ├─ Parse main.lua (regex or luaparse)
                              ├─ Extract function calls → intersect with API set
                              └─ Write to Firestore:
                                   games/{slug}: { apis: ["cls", "rectf", ...] }
                                   api_usage/{api}: { used_by: [slug1, slug2, ...] }
```

정적 분석을 선택한 이유:

| 방식 | 장점 | 단점 |
|---|---|---|
| 런타임 텔레메트리 | 실사용 데이터 | 동의 필요, 네트워크 의존, 스팸 위험 |
| 정적 분석 | 동의 불필요, 결정론적, 오프라인 | 존재 여부만 확인 (런타임 hit 아님) |
| 주기 `--scan` | 이미 구현됨 | 전체 게임 실행 → 느림 |

제거 결정에는 "존재 여부"면 충분 — 파일에 호출이 있는데 제거하면 깨지니까.

쿼리 예시:

```
  "아무도 안 쓰는 API" → api_usage where used_by is empty
  "cam_get 제거 시 영향받는 게임" → games where apis contains "cam_get"
  "가장 많이 쓰이는 top 10"  → api_usage order by len(used_by) desc limit 10
```

구현 난이도는 낮다 — 정규식 `\b(\w+)\s*\(`로 호출 식별자 추출 후 public API 집합과 교집합만 내면 된다. 오탐은 해롭지 않으니 (제거 안 함) 처음엔 regex로 충분, 필요시 `luaparse` AST로 업그레이드.

**단계**: ALPHA에서는 불필요. 로컬 `--scan --coverage`로 충분하다. GAMMA(퍼블리싱) 단계에서 Firebase Function에 추가.

## Gameplay Trace (`--trace`)

각 프레임의 상태(VRAM 해시, 활성 입력, 새로 출력된 로그)를 JSONL 형식으로 저장한다. AI가 게임 플레이를 분석하거나 버그 리포트를 자동화하는 데 활용.

```bash
node mono-test.js main.lua --frames 100 --input "5:right,20:a" --trace session.jsonl
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

## Golden Snapshot Regression (`--golden`)

데모 게임의 특정 프레임에서의 VRAM 해시를 "정상 상태"로 기록해 두고, 엔진 변경 후에도 동일한 해시가 나오는지 자동 검증한다.

### 기록

```bash
node mono-test.js main.lua --frames 120 --golden game.golden --golden-update --seed 42
# → 30, 60, 90, 120 프레임마다 해시를 기록
```

### 검증

```bash
node mono-test.js main.lua --frames 120 --golden game.golden --seed 42
# → 기록된 해시와 비교
```

### Golden 파일 포맷

```
# mono golden snapshots
# seed=42 colors=1
30 313b8c88
60 6337619a
90 5773643e
120 af0d75fb
```

### 출력 예시 (실패)

```
=== GOLDEN SNAPSHOTS ===
Targets: 4
Passed:  1
Failed:  3

Failures:
  frame 30: expected deadbeef, got 313b8c88
  frame 60: expected cafef00d, got 6337619a
  frame 90: expected 12345678, got 5773643e
```

### 활용

- **엔진 회귀 테스트**: 엔진 수정 후 모든 데모의 golden을 돌려 영향받은 데모를 즉시 파악
- **CI 통합**: PR 빌드 시 자동 실행 → 의도치 않은 렌더링 변경 차단
- **버그 재현 고정**: 버그 발생 프레임의 해시를 golden으로 저장 → 수정 후 다른 해시가 나오면 고쳐진 것

## Performance Benchmark (`--bench`)

각 프레임의 update+draw 실행 시간과 메모리 사용량을 측정하여 성능 리그레션을 감지한다.

```bash
node mono-test.js main.lua --frames 300 --bench --quiet
```

### 출력 예시

```
=== BENCHMARK ===
Frames: 300
min:    0.035ms
avg:    0.086ms
p50:    0.056ms
p95:    0.192ms
p99:    0.395ms
max:    2.409ms
budget: 33.333ms (30 FPS)
over:   0 frames (0.0%)

Heap:   6.86MB used / 10.70MB total
RSS:    63.53MB
```

### 메트릭

- **min/avg/p50/p95/p99/max**: 프레임 시간 분포 (낮을수록 좋음)
- **budget**: 30 FPS 목표(33.33ms) 대비 초과 프레임 수
- **Heap**: Node.js V8 힙 사용량
- **RSS**: 프로세스 전체 메모리

### 활용

- **엔진 변경 전후 비교**: 렌더링 최적화가 실제로 효과 있는지 수치로 확인
- **CI 성능 게이트**: p99 > 33ms면 빌드 실패 처리
- **프로파일링**: avg가 올라가면 어떤 프레임에서 튀는지 `--trace`와 함께 디버깅

## Fuzz Testing (`--fuzz`)

N번 게임을 실행하면서 각 실행마다 랜덤 입력 시퀀스를 주입해 엔진 크래시와 예외를 찾는다.

```bash
node mono-test.js main.lua --frames 60 --fuzz 100
```

### 입력 생성

- 실행마다 결정론적 seed (`r * 6037 + 13`) 사용 → 실패 케이스 재현 가능
- 실행마다 1~20개의 랜덤 입력 이벤트 (프레임+키)
- 키는 `up/down/left/right/a/b` 중 랜덤 선택

### 출력 예시

```
=== FUZZ RESULTS ===
Runs:     100
OK:       100
Crashes:  0 (0.00%)
Unique errors: 0
```

### 실패 시 출력

```
=== FUZZ RESULTS ===
Runs:     100
OK:       97
Crashes:  3 (3.00%)
Unique errors: 2

Error samples (sorted by frequency):
  [2x, first seed=6050] attempt to index nil value (frame N)
  [1x, first seed=24161] bad argument to rectf (line N)
```

- 동일 에러는 프레임 번호와 라인 번호를 정규화하여 그룹화
- `first seed`를 수동 재현에 활용: `--seed <값>`으로 동일 입력 재생성 가능 (수동으로)

### 활용

- **퍼블리싱 전 안정성 검증**: 유저 게임을 등록하기 전 엔진에 투입해 크래시 유무 확인
- **새 API 검증**: 엔진에 새 함수 추가 후 랜덤 입력으로 엣지 케이스 탐지
- **CI 안정성 게이트**: 크래시율이 0%가 아니면 merge 차단

## Scan Mode (`--scan`)

디렉토리 하위의 모든 `main.lua`를 재귀적으로 찾아서 각각 격리된 subprocess로 실행한다. 엔진 변경 후 전체 데모의 호환성을 한 번에 검증하거나, 퍼블리싱 시스템에서 여러 유저 게임을 일괄 검수하는 용도.

```bash
node mono-test.js --scan ./demo --frames 30
```

### 출력 예시

```
=== SCAN /Users/ssk/work/mono/demo ===
Found 12 game(s)

  ✓ PASS  engine-test/main.lua                        53ms
  ✓ PASS  pong/main.lua                               45ms
  ...

=== SCAN RESULTS ===
Total:  12
Passed: 12
Failed: 0
SCAN: PASS ✓
```

### 실패 시 출력

```
  ✓ PASS  engine-test/main.lua                        53ms
  ✗ FAIL  broken-game/main.lua                        12ms
         update error (frame 5): attempt to index nil value
```

- 각 게임은 **독립된 subprocess**로 실행 → 한 게임이 크래시해도 다른 게임에 영향 없음
- 첫 에러 라인을 요약 표시
- 실패 존재 시 exit code 1 (CI 게이트 역할)

### 활용

- **엔진 변경 영향 검증**: 엔진 수정 후 모든 데모가 여전히 작동하는지 1초 이내 확인
- **버전 호환성**: 구버전 게임이 새 엔진에서 돌아가는지 일괄 검증
- **퍼블리싱 검수**: monogame-storage에 올라온 유저 게임을 자동으로 스모크 테스트
- **CI 통합**: PR마다 모든 데모 + 모든 유저 게임 실행 → 실패 시 merge 차단

## 향후 확장

- `.mono/CONTEXT.md`에 mono-test 사용법 자동 포함
