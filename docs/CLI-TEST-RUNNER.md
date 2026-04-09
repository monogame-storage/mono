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

## 향후 확장

- `--snapshot frame5.txt` 로 특정 프레임 vdump 저장/비교
- `--diff expected.txt` 로 기대 출력과 비교 (regression test)
- `.mono/CONTEXT.md`에 mono-test 사용법 자동 포함
