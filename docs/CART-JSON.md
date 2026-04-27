# cart.json — Game Manifest

게임 카트리지의 메타데이터 파일. 엔진과 플랫폼이 게임을 식별하고 요구 사항을 판단하는 데 사용한다.

**`cart.json`이 없으면 레거시 게임으로 취급한다** (160×120, 필수 입력 없음).

---

## 위치

```
cart/
├── cart.json      ← 여기
├── main.lua
├── title.lua
└── game.lua
```

에디터 배포, Android 패키징, 스토어 등록 모두 이 파일을 기준으로 한다.

---

## 포맷

```json
{
  "mono": 1,
  "engine": "0.4",
  "title": "Pong",
  "description": "Classic paddle game",
  "required": ["dpad"]
}
```

---

## 필드

| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `mono` | number | Y | 매니페스트 포맷 버전. 현재 `1`. |
| `engine` | string | N | 엔진 버전 (`"major.minor"`). 없으면 `"0.3"` 폴백. |
| `title` | string | Y | 게임 타이틀. 스토어, 타이틀바 등에 표시. |
| `description` | string | N | 한 줄 소개. |
| `required` | string[] | N | 게임에 필수인 입력 장치 목록. |

---

## `required` — 필수 입력 장치

Android의 `<uses-feature android:required="true">`와 같은 개념.
이 목록에 있는 장치가 없는 환경에서는 게임이 플레이 불가능하다고 선언하는 것이다.

| 값 | 의미 | 비고 |
|------|------|------|
| `dpad` | 방향 입력 (4방향 + 대각선) | 게임패드 또는 키보드 방향키 |
| `touch` | 터치 입력 | `touch_start()` 등 로우 터치 API 사용 |
| `motion` | 기울기 / 회전 센서 | 가속도계 + 자이로 통합. WebView `DeviceMotionEvent` 기반 |

**버튼(`a`, `b`, `start`, `select`)은 선언하지 않는다** — 모든 Mono 환경(게임패드, 키보드)에서 항상 제공되므로 필수 장치 선언이 불필요.

### 활용

- **스토어 필터링** — `required: ["motion"]`인 게임은 센서 없는 기기의 스토어에서 숨김
- **게임패드 자동 구성** — `required`에 `dpad`가 없으면 방향키 UI 생략 가능
- **호환 경고** — 터치 전용 기기에서 `required: ["dpad"]` 게임을 열면 경고

---

## 레거시 폴백

`cart.json`이 없거나 `engine` 필드가 없는 게임:

| 항목 | 기본값 |
|------|--------|
| 엔진 | `"0.3"` |
| 해상도 | 160×120 |
| 필수 입력 | 없음 (모든 환경에서 실행 시도) |
| 타이틀 | 디렉토리 이름 |

---

## 미결정

- **`author`** — 개발자 이름. 스토어/퍼블리싱 시스템 설계에 따라 추가 여부 결정.
- **`version`** — 게임 버전. 퍼블리싱 파이프라인에서 관리할지 `cart.json`에 넣을지 미정.

---

## 관련 문서

- [GAME-STANDARD.md](./GAME-STANDARD.md) — 게임 구조 / 컨트롤 규약
- [SPEC.md](./SPEC.md) — 콘솔 하드웨어 스펙
- [API.md](./API.md) — 엔진 API 레퍼런스
