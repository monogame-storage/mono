# Mono

> 제약이 곧 창의력이다.

1960년, 편집자 Bennett Cerf는 Dr. Seuss에게 50개 단어만으로 책을 쓸 수 있냐고 $50를 걸었다. 결과물 *Green Eggs and Ham*은 8백만 부가 팔렸고, 뉴요커는 "50개 단어라는 사실을 의식하기 어렵다"고 평했다. ([Wikipedia](https://en.wikipedia.org/wiki/Green_Eggs_and_Ham))

Rider University의 Catrinel Haught-Tromp는 이를 **Green Eggs and Ham Hypothesis**로 발전시켰다 — 임의의 제약을 준 그룹이 자유롭게 쓴 그룹보다 더 창의적인 결과를 냈고, 제약이 사라진 뒤에도 높아진 창의성이 유지됐다. 제약은 "압도적인 선택지를 관리 가능한 범위로 줄여, 익숙하지 않은 경로를 탐색하게 만든다." ([논문](https://www.cct.umb.edu/630/files/HaughtTromp2017-GreenEggsandHam.pdf), [기사](https://psmag.com/news/constraints-can-be-a-catalyst-for-creativity/))

Mono는 이 원리를 게임 개발에 적용한다. 160×144 해상도, 그레이스케일, Lua — 제약 안에서 게임을 만드는 판타지 콘솔.

## 콘솔 스펙

- **해상도**: 160×144 고정
- **컬러**: 그레이스케일 (1비트=2색, 2비트=4색, 4비트=16색)
- **프레임레이트**: 30fps
- **입력**: 방향키 + A(z), B(x), Start(Enter), Pause(Space)
- **언어**: Lua 5.4 (Wasmoon)
- **VRAM**: Uint8Array[23,040] — 1픽셀 = 1바이트

## 구조

```
runtime/engine.js   엔진 (캔버스 + VRAM + Lua VM)
engine-test/        엔진 테스트 (시각 + 자동 suite)
demos/bounce/       데모 게임 (바운싱 볼)
docs/SPEC.md        스펙 문서
```

## 시작하기

```bash
# 로컬 서버 실행
python3 -m http.server 8090

# 브라우저에서 열기
open http://localhost:8090
```

## API

```lua
-- 콜백
function _init() end   -- 1회
function _update() end -- 30fps
function _draw() end   -- 30fps

-- 그래픽
cls(c)                  -- 화면 지우기
pix(x,y,c)             -- 픽셀 쓰기
gpix(x,y)              -- 픽셀 읽기
line(x0,y0,x1,y1,c)    -- 선
rect(x,y,w,h,c)        -- 사각형 테두리
rectf(x,y,w,h,c)       -- 채운 사각형
circ(x,y,r,c)          -- 원 테두리
circf(x,y,r,c)         -- 채운 원
text(str,x,y,c)        -- 텍스트 (4x7 폰트)

-- 입력
btn(key)                -- 누르고 있는지 (up/down/left/right/a/b/start)
btnp(key)               -- 이번 프레임에 눌렸는지

-- VRAM
vrow(y)                 -- 행 hex 덤프
vdump()                 -- 전체 hex 덤프

-- 상수
SCREEN_W                -- 160
SCREEN_H                -- 144
COLORS                  -- 팔레트 크기 (2, 4, 16)
```

## 문서

- [콘솔 스펙](docs/SPEC.md)

## 라이선스

MIT
