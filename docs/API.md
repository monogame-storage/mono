# Mono API Reference v1.0 "Mono"

## 라이프사이클

게임은 3개의 콜백 함수로 구성된다:

```typescript
function init(): void    // 게임 시작 시 1회 호출
function update(): void  // 매 프레임 로직 (30fps)
function draw(): void    // 매 프레임 렌더링
```

## 그래픽

Color 타입: `0` (BLACK) | `1` (DARK) | `2` (LIGHT) | `3` (WHITE)

```typescript
cls(color?: Color): void
// 화면 전체를 지정 색으로 클리어. 기본값 0(BLACK)

pix(x: number, y: number, color: Color): void
// 단일 픽셀을 찍는다

line(x0: number, y0: number, x1: number, y1: number, color: Color): void
// 두 점 사이에 직선을 그린다

rect(x: number, y: number, w: number, h: number, color: Color): void
// 사각형 테두리를 그린다

rectf(x: number, y: number, w: number, h: number, color: Color): void
// 사각형을 채워서 그린다

circ(cx: number, cy: number, r: number, color: Color): void
// 원 테두리를 그린다

circf(cx: number, cy: number, r: number, color: Color): void
// 원을 채워서 그린다

text(str: string, x: number, y: number, color: Color): void
// 내장 4×7 픽셀 폰트로 텍스트를 그린다 (대문자, 숫자, 기본 특수문자)
```

## 스프라이트

```typescript
sprite(id: number, data: string): void
// 16×16 스프라이트를 등록한다
// data: "00030000..." 형태의 64자 문자열 (0~3)

spr(id: number, x: number, y: number, flipX?: boolean, flipY?: boolean): void
// 등록된 스프라이트를 화면에 그린다
// flipX/flipY로 좌우/상하 반전 가능
```

## 타일맵

```typescript
mget(cx: number, cy: number): number
// 타일맵 셀의 스프라이트 ID를 반환

mset(cx: number, cy: number, id: number): void
// 타일맵 셀에 스프라이트 ID를 설정

map(mx: number, my: number, mw: number, mh: number, sx: number, sy: number): void
// 타일맵의 지정 영역을 화면에 그린다
// (mx,my)부터 (mw×mh) 셀을 화면 좌표 (sx,sy)에 렌더링
```

## 입력

```typescript
type Key = "up" | "down" | "left" | "right" | "a" | "b"

btn(key: Key): boolean
// 해당 버튼이 현재 눌려있으면 true

btnp(key: Key): boolean
// 해당 버튼이 이번 프레임에 새로 눌렸으면 true (이전 프레임에는 안 눌려있었을 때)
```

## 사운드

```typescript
note(channel: 0 | 1, note: string, duration: number): void
// 지정 채널에서 음을 재생
// note: "C4", "A#3", "G5" 등 음이름+옥타브
// duration: 초 단위 재생 시간

stop(channel?: 0 | 1): void
// 채널 정지. 인자 없으면 전체 정지
```

## 유틸리티

```typescript
rnd(max: number): number   // 0 이상 max 미만 랜덤 실수
flr(n: number): number     // 내림 (Math.floor)
abs(n: number): number     // 절대값
min(a: number, b: number): number
max(a: number, b: number): number
sin(n: number): number
cos(n: number): number
```

## 전역 상태

```typescript
frame: number  // 현재 프레임 번호 (0부터 시작, 매 프레임 +1)
```

## 추후 추가 검토 중

- `cam(x, y)` — 카메라 오프셋 (스크롤 게임용)
- `overlap(x1,y1,w1,h1, x2,y2,w2,h2)` — AABB 충돌 판정 헬퍼
- 투명색 처리 방식 (색 0을 투명으로? 별도 투명 인덱스?)
- `save(key, value)` / `load(key)` — 로컬 데이터 저장
