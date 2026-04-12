# Developer Scenarios

개발자가 Mono 플랫폼에서 거치는 모든 시나리오를 한 곳에 모은 목록입니다. 각 항목은 향후 화면/플로우 설계의 체크리스트로 사용됩니다.

> **Scope**: 모바일 레이아웃 중심. 태블릿/데스크톱 전용 기능은 별도 섹션에 표시.

---

## 1. 입문 & 계정

- 개발자 가입하기
- 개발자 홈 진입 (대시보드)
- 개발자 설정
  - 프로필 & 표시 이름
  - 이메일 & 비밀번호
  - 개인정보
  - 알림
  - API 토큰
  - 도움말 & 문서
- 로그아웃

---

## 2. 게임 만들기 (Editor)

### 진입
- 새 게임 만들기 → 에디터 진입
- 기존 게임 편집 → Game Detail → 에디터 진입

### AI 협업
- 프롬프트로 AI 개발 의뢰
- AI 작업 진행 상황 모니터링
  - 파일별 상태 아이콘 (editing / creating / queueing)
  - 스트리밍 메시지
- AI 작업 중단하기 (Stop)
- 중단된 작업 삭제하기 (tail 상태일 때만, `Delete work`)
- 스냅샷 복구하기
  - 해당 프롬프트의 restore 아이콘 클릭
  - cascade 경고 팝업 ("이후 N개 작업이 삭제됩니다")
  - 프롬프트 편집 후 재제출 → AI 새 작업 시작

### 테스트 & 검증
- 편집 중 버전 플레이하기 (`Play dev`)
- 게임패드 보기 / 숨기기 토글
- 콘솔 로그 확인 (`screen` / `gamepad` / `log` / `engine` 탭)

### 편집 메시지 상태
- **Working**: 작업 진행 중, `Stop` 버튼 활성
- **Completed**: 완료, 스냅샷 생성, 프롬프트에 `restore` 아이콘
- **Stopped (tail)**: 중단 직후, `Delete work` 버튼
- **Stopped (non-tail)**: 뒤에 새 작업 쌓임 → 암묵 수락, 프롬프트에 `restore` 아이콘으로 전환

---

## 3. 게임 관리

### 목록 & 검색
- 내 게임 목록 보기 (My Games)
- 상태별 필터링
  - All
  - Draft
  - Review (심사중)
  - Rejected (심사거절)
  - Published (배포됨)
  - Unpublished (배포취소)

### 개별 게임 상세 (Game Detail)
- 현재 상태 확인 (상태 뱃지 + 버전 + 배포 일자)
- 주요 액션
  - `Play dev` — 편집 중 버전 재생
  - `Preview live` — 라이브 버전을 유저 Preview 화면으로 점프
  - `Edit` — 에디터 진입
- 통계 확인 (플레이 수, 일별 차트 — 최근 7일)
- 최근 리뷰 확인
- 릴리스 히스토리 (버전 타임라인)

---

## 4. 배포 (Publishing)

### 릴리스 작성
- 버전 자동 증분 (편집 가능)
- 코드 변경사항 요약 확인 (파일별 `+/-` 라인 수)
- 메타데이터 변경사항 확인
- 릴리스 노트 작성 (optional)
- 가시성 선택 (Public / Unlisted)

### 배포 전 체크
- 제목 / 설명 / 태그 존재 여부
- 썸네일 (160 × 120, PNG)
- Headless 테스트 통과 여부
- 릴리스 노트 (warning level, optional)

### 제출
- `Submit for review` 클릭 → 심사중 상태로 전환

### 배포 후
- 심사 상태 확인 (Review / Published / Rejected)
- 심사 거절 대응 (거절 사유 확인 → 수정 → 재제출)
- 배포 취소 (Unpublish)
- 재배포 (Republish)

---

## 5. 고급 (태블릿 / 데스크톱 전용)

모바일 레이아웃에서는 감춤. 다른 레이아웃에서만 노출.

- 소스 코드 직접 편집 (multi-file)
- 에셋 관리
  - 이미지 업로드 / 교체 (스프라이트, 배경)
  - 팔레트 제한 검증
  - 카트 용량 확인
- 협업자 초대 / 권한 관리
- 게임 포크 (다른 사람 게임 복제)

---

## 6. 상태 머신

### 게임 상태
```
Draft  ─→  Review  ─→  Published  ─→  Unpublished
             │              │
             └─ Rejected ←──┘
                   │
                   └─ (수정 후 재제출) ─→ Review
```

### Editor 채팅 메시지 상태
```
Working  ─→  Completed
   │            │
   │            └→ [restore ↻ 영구]
   │
   └→ Stopped (tail)  ─→ Delete work 사용 가능
                    │
                    └→ 새 프롬프트 입력
                         │
                         └→ Stopped (non-tail): restore ↻ 로 전환
```

---

## 7. 아직 결정 안 된 항목

- **심사 주체** — 자동 검증 / 운영자 수동 검토 / 혼합?
- **심사 소요 시간** — 예상 시간 표시 필요한가?
- **버전 번호 전략** — 자동 semver / 수동 입력?
- **롤백** — 특정 버전으로 라이브를 되돌릴 수 있는가?
- **삭제 정책** — 게임 완전 삭제는 가능한가? 삭제 후 복구?
- **수익화** — 광고 / 프리미엄 / 후원?
- **협업 공유 범위** — 초대받은 협업자는 어디까지 볼 수 있나?

---

## Related docs

- [GAME-STANDARD.md](./GAME-STANDARD.md) — 게임 구조 / 컨트롤 규약
- [DEV.md](./DEV.md) — Mono 엔진 API 레퍼런스
- [AI-PITFALLS.md](./AI-PITFALLS.md) — AI 코드 생성 시 흔한 실수
