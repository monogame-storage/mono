# Mono Android Wrapper

Mono 게임을 Android APK로 패키징하는 래퍼.

## Quick Start

```bash
# 1. 프로젝트 생성
./scripts/create-android.sh ~/my-game --project-name "My Game" --org com.example

# 2. cart/main.lua 작성 (API는 cart/.mono/CONTEXT.md 참조)

# 3. 실행
cd ~/my-game && ./run.sh
```

## Game Files

게임 파일은 `cart/`에 넣는다. 엔진 API 문서는 `cart/.mono/CONTEXT.md`에 있다.

```
cart/
  main.lua              # 엔트리 포인트 (필수)
  shader.json           # 셰이더 설정 (chain 배열로 on/off)
  .mono/                # 엔진 (자동 생성, 수정 금지)
    CONTEXT.md          # ★ API 레퍼런스 — 여기를 읽어라
    engine.js
    VERSION
```

## Commands

```bash
./run.sh                    # debug 빌드 + 설치 + 실행
./run.sh --release          # release (signed) 빌드 + 설치 + 실행
./run.sh --clean            # 클린 빌드
./update-engine.sh          # cart/.mono/ 엔진만 최신으로 교체 ($MONO_ROOT 필요)
./update-icon.sh icon.png   # 앱 아이콘 교체 (512x512 PNG, macOS only)
./gradlew bundleRelease     # 릴리스 AAB (signing 설정 필요)
```

## Environment

```bash
export MONO_ROOT="$HOME/work/mono"                        # mono 레포 루트
export GOOGLEPLAY_TEMPLATE_ROOT="$HOME/mono/android/googleplay-template"  # 플레이스토어 템플릿
```

## Shader

`cart/shader.json`의 `chain` 배열만 수정하면 된다. 파라미터는 기본값 포함.

```json
{ "chain": ["tint", "lcd"] }
```

## Requirements

- Android SDK (min 24, target 36)
- ImageMagick (`brew install imagemagick`) — update-icon.sh용
