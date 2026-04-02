# LLM Game Verification Guide

LLM이 Mono 게임엔진 코드를 작성/수정하고 결과를 자동 검증하는 방법 가이드.

## 방법 1: `mono-test.js` (헤드리스 CLI) — 추천

브라우저 없이 Node.js에서 직접 Lua 코드를 실행하고 검증.

### 기본 사용법

```bash
# 파일 실행
node runtime/mono-test.js game.lua --frames 10 --ascii

# 인라인 코드 실행 (파일 없이)
node runtime/mono-test.js --source 'cls(0) rectf(10,10,20,20,1) text("HI",50,50,1)' --ascii

# 테스트 스위트 실행
node runtime/mono-test.js engine-test/suite.lua --suite --console

# npm 스크립트
npm test                    # suite.lua 전체 실행
npm run test:bounce         # bounce 데모 30프레임
npm run verify -- game.lua --frames 5 --ascii
```

### 출력 옵션

| 옵션 | 설명 | LLM 활용 |
|------|------|----------|
| `--ascii` | 4:1 축소 ASCII 아트 | 빠른 시각적 확인 |
| `--ascii-full` | 원본 해상도 ASCII | 정밀 확인 |
| `--vdump` | VRAM hex 덤프 (160x144) | 픽셀 단위 검증 |
| `--vrow Y` | 특정 행 hex 덤프 | 특정 위치 확인 |
| `--png FILE` | PNG 이미지 저장 | 시각적 검증 (Read로 확인) |
| `--region X,Y,W,H` | 영역 크롭 | 특정 영역만 검사 |
| `--snapshot FILE` | vdump 저장 | 기준 스냅샷 생성 |
| `--diff FILE` | 스냅샷 비교 | 회귀 테스트 |
| `--suite` | PASS/FAIL 파싱 | 테스트 자동화 |
| `--input "F:K"` | 입력 주입 | 인터랙션 테스트 |
| `--quiet` | 프레임 로그 억제 | 출력 간소화 |
| `--console` | Lua print() 출력 | 디버그 |

### LLM 자동 루프 패턴

```
1. game.lua 수정 (Edit tool)
2. node runtime/mono-test.js game.lua --frames 5 --ascii (Bash tool)
3. ASCII 아트로 화면 확인
4. 문제 있으면 수정 반복
```

### 인라인 코드 테스트 (파일 없이)

```bash
# 도형 그리기 테스트
node runtime/mono-test.js --source 'cls(0) circ(80,72,30,1)' --ascii

# 특정 픽셀 검증
node runtime/mono-test.js --source 'cls(0) pix(80,72,1) print(gpix(80,72))' --console --quiet

# 텍스트 렌더링 확인
node runtime/mono-test.js --source 'cls(0) text("HELLO WORLD",20,68,1)' --ascii
```

### 입력 시나리오 테스트

```bash
# 3프레임에서 A 버튼, 5프레임에서 오른쪽 입력
node runtime/mono-test.js game.lua --frames 10 --input "3:a,5:right" --ascii
```

### 회귀 테스트

```bash
# 기준 스냅샷 생성
node runtime/mono-test.js game.lua --frames 5 --snapshot expected.txt

# 수정 후 비교
node runtime/mono-test.js game.lua --frames 5 --diff expected.txt
# → DIFF: MATCH ✓  또는  DIFF: MISMATCH ✗
```

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

| 항목 | mono-test.js (CLI) | Preview (브라우저) |
|------|--------------------|--------------------|
| 속도 | 빠름 (~1초) | 느림 (~5초) |
| 설정 | `node runtime/mono-test.js` | 서버 + 브라우저 |
| 시각 확인 | ASCII/PNG | 스크린샷 |
| 픽셀 검증 | vdump/gpix | Mono.vdump() |
| 입력 테스트 | `--input` | preview_click/key |
| 이미지 로딩 | pngjs (제한적) | 완전 지원 |
| 셰이더 | 미지원 | 지원 |
| 자동화 | 쉬움 | 보통 |

## 추천 워크플로

**코드 작성 → 검증 루프:**

1. **빠른 검증**: `mono-test.js --ascii` (1초 이내)
2. **정밀 검증**: `mono-test.js --png` → `Read` 도구로 확인
3. **시각적 검증**: Preview 스크린샷 (셰이더/이미지 포함 시)
4. **회귀 테스트**: `--snapshot` + `--diff`
5. **유닛 테스트**: `--suite` 모드로 PASS/FAIL 파싱
