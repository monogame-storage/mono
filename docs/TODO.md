# Mono TODO

스펙 대비 구현 상태. ✅ 구현됨, ⬜ 미구현.

## 디스플레이
- ✅ 160×120 고정 해상도
- ✅ 30fps 게임 루프
- ✅ 1/2/4비트 그레이스케일 팔레트
- ✅ VRAM (Uint8Array, 1px=1byte)
- ✅ canvas 2D flush
- ⬜ WebGL flush (셰이더/CRT 필터 등)

## 그래픽
- ✅ cls, pix, gpix
- ✅ line (Bresenham)
- ✅ rect, rectf
- ✅ circ, circf (midpoint)
- ✅ text (4×7 비트맵 폰트)
- ✅ vrow, vdump (VRAM hex 덤프)
- ⬜ 스프라이트 (defSprite, spr)
- ⬜ 타일맵 (mget, mset, map)
- ⬜ 카메라 (cam, cam_get)

## 입력
- ✅ btn, btnp (키보드)
- ✅ 키보드 매핑 (Arrow/WASD, Z=A, X=B, Enter=Start)
- ✅ pause 토글 (Space, 엔진 레벨)
- ✅ 디버그 모드 토글 (1 키)
- ⬜ 마우스 입력 (mouse_x, mouse_y, mouse_btn)
- ⬜ 터치 입력 (→ 마우스 자동 매핑)
- ⬜ 중력센서 (accel_x, accel_y, accel_z)
- ⬜ 입력 추상화 (터치/틸트 → btn 자동 매핑)

## 사운드
- ⬜ Web Audio API 기반 사운드 시스템

## 엔진
- ✅ Wasmoon Lua 5.4 VM
- ✅ _init / _update / _draw 콜백
- ✅ PAUSED 오버레이
- ⬜ Wasmoon 로컬 번들 (현재 CDN 의존)
- ⬜ 헤드리스 모드 (canvas 없이 Node.js 실행)
- ⬜ 디버그 오버레이 (히트박스 시각화)
- ⬜ 프레임 카운터 / rnd / math 유틸

## 테스트
- ✅ 시각 테스트 5개 (pixel, line, rect, circ, text)
- ✅ 자동 테스트 suite (88 assertions)
- ✅ VRAM 덤프 모달
- ⬜ 입력 테스트 (btn, btnp)
- ⬜ 헤드리스 테스트 러너 (Node.js)

## 인프라
- ✅ 홈 페이지 (테스트/데모 링크)
- ✅ 데모 게임 (bounce)
- ⬜ 에디터 (Monaco 기반)
- ⬜ 게임 포털 / 공유 시스템
