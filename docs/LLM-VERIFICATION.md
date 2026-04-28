# LLM Game Verification Guide

LLM이 Mono 게임엔진 코드를 작성/수정하고 결과를 자동 검증하는 방법 가이드.

## 방법 1: `mono-runner.js` (헤드리스 CLI) — 추천

브라우저 없이 Node.js에서 직접 Lua 코드를 실행하고 검증.

### 기본 사용법

```bash
# 파일 실행
node dev/headless/mono-runner.js main.lua --frames 10 --vdump

# 인라인 코드 실행 (파일 없이)
node dev/headless/mono-runner.js --source 'cls(0) rectf(10,10,20,20,1) text("HI",50,50,1)' --vdump

# 테스트 스위트 실행
node dev/headless/mono-runner.js engine-test/suite.lua --suite --console

# npm 스크립트
npm test                    # suite.lua 전체 실행
npm run test:bounce         # bounce 데모 30프레임
npm run verify -- main.lua --frames 5 --vdump
```

### 출력 옵션

| 옵션 | 설명 | LLM 활용 |
|------|------|----------|
| `--vdump` | VRAM hex 덤프 (160x120, 0-f per pixel) | 픽셀 단위 검증, 시각 확인 |
| `--vrow Y` | 특정 행 hex 덤프 | 특정 위치 확인 |
| `--png FILE` | PNG 이미지 저장 | 사람 확인 (Read로 이미지 읽기) |
| `--region X,Y,W,H` | 영역 크롭 | 특정 영역만 덤프 |
| `--snapshot FILE` | vdump 저장 | 기준 스냅샷 생성 |
| `--diff FILE` | 스냅샷 비교 | 회귀 테스트 |
| `--suite` | PASS/FAIL 파싱 | 테스트 자동화 |
| `--input "F:K"` | 입력 주입 | 인터랙션 테스트 |
| `--quiet` | 프레임 로그 억제 | 출력 간소화 |
| `--console` | Lua print() 출력 | 디버그 |
| `--until "TEXT"` | 텍스트 매칭 시 자동 중단 | 게임 종료 감지 |
| `--runs N` | N회 반복 실행 + 통계 | 밸런스 테스트 |
| `--seed N` | 랜덤 시드 고정 | 재현 가능한 테스트 |

> **vdump is the source of truth.** 화면 상태는 항상 hex 형태(`0` = empty, `f` = brightest)로 확인한다. 과거에 있던 `--ascii` / `--ascii-full` density-ramp 출력은 제거되었다 — 같은 데이터를 다른 알파벳으로 재표현하는 중복이었다.

### LLM 자동 루프 패턴

```
1. main.lua 수정 (Edit tool)
2. node dev/headless/mono-runner.js main.lua --frames 5 --vdump (Bash tool)
3. vdump hex로 화면 확인 (또는 --region으로 좁힘)
4. 문제 있으면 수정 반복
```

### 인라인 코드 테스트 (파일 없이)

```bash
# 도형 그리기 테스트
node dev/headless/mono-runner.js --source 'cls(0) circ(80,72,30,1)' --vdump

# 특정 픽셀 검증
node dev/headless/mono-runner.js --source 'cls(0) pix(80,72,1) print(gpix(80,72))' --console --quiet

# 텍스트 렌더링 확인 (좁은 영역만)
node dev/headless/mono-runner.js --source 'cls(0) text("HELLO WORLD",20,68,1)' --vdump --region 18,66,80,10
```

### 입력 시나리오 테스트

```bash
# 3프레임에서 A 버튼, 5프레임에서 오른쪽 입력
node dev/headless/mono-runner.js main.lua --frames 10 --input "3:a,5:right" --vdump
```

### 회귀 테스트

```bash
# 기준 스냅샷 생성
node dev/headless/mono-runner.js main.lua --frames 5 --snapshot expected.txt

# 수정 후 비교
node dev/headless/mono-runner.js main.lua --frames 5 --diff expected.txt
# → DIFF: MATCH ✓  또는  DIFF: MISMATCH ✗
```

### Fast-Forward Testing

게임 시간을 빨리감기하여 결과를 즉시 확인. 실제 5분짜리 게임을 1초에 시뮬레이션.

```bash
# 게임 종료 조건 감지 (예: "WINNER" 출력 시 자동 중단)
node dev/headless/mono-runner.js main.lua --frames 10000 --until "WINNER" --quiet --console
# → --until "WINNER" matched at frame 297 (9.9s game time)

# 밸런스 테스트: 10판 돌려서 승률 확인
node dev/headless/mono-runner.js main.lua --frames 10000 --until "WINNER" --quiet --runs 10
# → Results:
#   "WINNER: CPU 9-0": 7/10 (70%)
#   "WINNER: P2 9-5": 3/10 (30%)

# 재현 가능한 테스트: 특정 시드로 고정
node dev/headless/mono-runner.js main.lua --frames 1000 --seed 42 --console --quiet

# 스트레스 테스트: 10000프레임 에러 없이 완주하는지
node dev/headless/mono-runner.js main.lua --frames 10000 --quiet
```

**활용 예시:**
- AI 난이도 조정 → `--runs 10`으로 승률 확인 → 파라미터 조정 반복
- 경계값 버그 탐색 → 대량 프레임 돌려서 crash 여부 확인
- 게임 종료 로직 검증 → `--until`로 종료 조건 도달 확인

### VRAM Bot (자동 플레이)

`--bot`으로 VRAM을 읽어서 자동 조작하는 봇을 실행. 양쪽 AI 대전, 밸런스 테스트에 활용.

```bash
# 내장 봇 (기본 추적 AI)
node dev/headless/mono-runner.js main.lua --frames 10000 --until "WINNER" --bot --quiet

# 외부 봇 스크립트
node dev/headless/mono-runner.js main.lua --frames 10000 --until "WINNER" --bot bot.lua --quiet

# 10판 AI vs Bot 밸런스 테스트
node dev/headless/mono-runner.js main.lua --frames 20000 --until "WINNER" --bot --runs 10 --quiet
```

**봇 스크립트 작성법** (`bot.lua`):

```lua
-- _bot(): 매 프레임 _draw() 후 호출
-- gpix()로 VRAM을 읽고, 입력 키를 리턴
-- 리턴값: "up", "down", "left", "right", "a", "b" 또는 "up,a" (복합)
-- 리턴 false = 입력 없음

function _bot()
  -- 화면에서 공 찾기 (가장 밝은 픽셀 클러스터)
  local ball_y = -1
  local best = 0
  for y = 4, SCREEN_H - 5 do
    local count = 0
    for x = 48, 140 do
      if gpix(x, y) >= 12 then count = count + 1 end
    end
    if count > best then best = count; ball_y = y end
  end

  -- 패들 위치 찾기 (우측 밝은 바)
  local pad_y = 72
  local sum, cnt = 0, 0
  for y = 0, SCREEN_H - 1 do
    for x = 148, 156 do
      if gpix(x, y) >= 12 then sum = sum + y; cnt = cnt + 1 end
    end
  end
  if cnt > 0 then pad_y = sum / cnt end

  -- 추적
  if ball_y >= 0 then
    if ball_y < pad_y - 6 then return "up" end
    if ball_y > pad_y + 6 then return "down" end
  end
  return false
end
```

**원리**: 게임 내부 변수를 안 읽고 순수하게 화면(VRAM)만 보고 조작 → 어떤 게임이든 범용 적용 가능.

### 제한사항

`mono-runner.js`는 engine.js의 그래픽 프리미티브만 구현합니다. 다음 API는 미지원:
- ECS: `spawn()`, `kill()`, `pollCollision()`, `defVisual()`
- 스프라이트: `defSprite()`, `spr()`
- 타일맵: `mget()`, `mset()`, `map()`
- 사운드: `sfx()`, `bgm()`

이들 API를 사용하는 게임은 브라우저(Preview Tools)로 검증해야 합니다.

## 방법 2: Preview Tools (브라우저 기반)

Claude Preview MCP를 통해 실제 브라우저에서 게임을 실행하고 확인.

### 사용법

```
1. preview_start("mono")로 HTTP 서버 시작
2. preview_eval로 게임 페이지 이동
3. preview_screenshot으로 시각적 확인
4. preview_eval로 Mono.vdump() 호출하여 VRAM 텍스트 확인
5. preview_snapshot으로 접근성 트리 확인
```

### 장점
- 실제 브라우저 렌더링 (셰이더, 이미지 로딩 포함)
- 스크린샷으로 완전한 시각적 검증
- 브라우저 콘솔 에러 확인 가능

### 단점
- 서버 설정 필요
- 헤드리스보다 느림
- 입력 시뮬레이션이 복잡

## 방법 비교

| 항목 | mono-runner.js (CLI) | Preview (브라우저) |
|------|--------------------|--------------------|
| 속도 | 빠름 (~1초) | 느림 (~5초) |
| 설정 | `node dev/headless/mono-runner.js` | 서버 + 브라우저 |
| 시각 확인 | vdump hex / PNG | 스크린샷 |
| 픽셀 검증 | vdump / gpix | Mono.vdump() |
| 입력 테스트 | `--input` | preview_click/key |
| 이미지 로딩 | pngjs (제한적) | 완전 지원 |
| 셰이더 | 미지원 | 지원 |
| 자동화 | 쉬움 | 보통 |

## 추천 워크플로

**코드 작성 → 검증 루프:**

1. **빠른 검증**: `mono-runner.js --vdump` (1초 이내, 필요하면 `--region`으로 좁힘)
2. **사람 확인**: `mono-runner.js --png` → `Read` 도구로 이미지 열기
3. **시각적 검증**: Preview 스크린샷 (셰이더/이미지 포함 시)
4. **회귀 테스트**: `--snapshot` + `--diff`
5. **유닛 테스트**: `--suite` 모드로 PASS/FAIL 파싱
