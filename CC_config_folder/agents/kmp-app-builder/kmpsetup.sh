#!/bin/zsh
set -euo pipefail

# ========= 유틸 함수 =========
append_if_absent() {
  local FILE="$1"
  local LINE="$2"
  touch "$FILE"
  grep -Fqx "$LINE" "$FILE" || echo "$LINE" >> "$FILE"
}

log()  { echo "\n[INFO] $*"; }
warn() { echo "\n[WARN] $*"; }
ok()   { echo "\n[OK]   $*"; }

# ========= 사전 점검 =========
if [[ "$(uname -m)" != "arm64" ]]; then
  warn "Apple Silicon(arm64) 전용 튜닝 기준임. Intel 맥에서도 동작 가능하나 일부 최적화 상이함"
fi

ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
ENV_FILE="$HOME/.kmp-env"

# ========= Homebrew 설치 =========
if ! command -v brew >/dev/null 2>&1; then
  log "Homebrew 미설치 상태 감지됨. 설치 진행함"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # PATH 보정
  if [[ -d /opt/homebrew/bin ]]; then
    append_if_absent "$ZSHRC" 'eval "$(/opt/homebrew/bin/brew shellenv)"'
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
else
  ok "Homebrew 설치 확인됨"
fi

log "brew 업데이트 및 기본 패키지 설치 진행함"
brew update

# CLI 패키지
brew install git gradle kotlin cocoapods kdoctor mas wget unzip

# GUI 앱
brew install --cask android-studio intellij-idea-ce visual-studio-code temurin@17 android-commandlinetools

# 선택: Rosetta (일부 x86_64 바이너리 호환 목적)
softwareupdate --install-rosetta --agree-to-license 2>/dev/null || true

ok "기본 패키지 설치 완료됨"

# ========= Xcode / CLT 설정 =========
if ! xcode-select -p >/dev/null 2>&1; then
  log "Xcode Command Line Tools 미설치 상태 감지됨. 설치 다이얼로그 표시됨"
  xcode-select --install || true
else
  ok "Xcode Command Line Tools 확인됨"
fi

# 사용자가 Mac App Store로 Xcode 설치 필요
if [[ ! -d "/Applications/Xcode.app" ]]; then
  warn "Xcode 앱 미설치 상태 감지됨. App Store에서 Xcode 설치 필요함"
  warn "원한다면 'mas' 로그인 후 자동 설치 가능함: mas install 497799835"
else
  log "Xcode 초기화 진행함"
  sudo xcodebuild -runFirstLaunch || true
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer || true
  ok "Xcode 초기화 완료됨"
fi

# ========= ANDROID SDK 설정 =========
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
ANDROID_HOME="${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
mkdir -p "$ANDROID_SDK_ROOT"

# cmdline-tools 배치(홈브류 설치본 → 표준 경로 심볼릭 링크 구성)
log "Android cmdline-tools 연결 진행함"
CMDLINE_SRC="$(/usr/bin/find /opt/homebrew/Caskroom/android-commandlinetools -type d -name 'cmdline-tools' -maxdepth 3 2>/dev/null | head -n1 || true)"
if [[ -n "${CMDLINE_SRC:-}" ]]; then
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
  rm -f "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  ln -s "$CMDLINE_SRC" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  ok "cmdline-tools 링크 완료됨 → $ANDROID_SDK_ROOT/cmdline-tools/latest"
else
  warn "cmdline-tools 원본 경로 탐색 실패함. Android Studio에서 SDK 설치 진행 필요함"
fi

# PATH 및 환경변수 파일 생성
log "환경변수 파일 생성 진행함 → $ENV_FILE"
cat > "$ENV_FILE" <<'EOF'
# Kotlin Multiplatform / Android SDK 환경설정
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"

# Homebrew shellenv (Apple Silicon)
if [ -d /opt/homebrew/bin ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Java 17 (Temurin)
export JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
if [ -n "$JAVA_HOME" ]; then
  export PATH="$JAVA_HOME/bin:$PATH"
fi
EOF

append_if_absent "$ZSHRC" "source \"$ENV_FILE\""
# 즉시 반영
source "$ENV_FILE" || true
ok "환경변수 설정 완료됨(.zshrc에 자동 등록됨)"

# ========= SDK 구성 및 라이선스 동의 =========
SDKMGR="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"
if [[ -x "$SDKMGR" ]]; then
  log "Android SDK 구성 및 라이선스 동의 진행함"
  yes | "$SDKMGR" --licenses >/dev/null || true
  "$SDKMGR" --install \
    "platform-tools" \
    "platforms;android-34" \
    "platforms;android-35" \
    "build-tools;34.0.0" \
    "build-tools;35.0.0" \
    "emulator" \
    "cmdline-tools;latest" || true
  ok "SDK 패키지 설치 절차 완료됨"
else
  warn "sdkmanager 실행 불가 상태임. Android Studio 최초 실행 후 SDK 설치 필요함"
fi

# ========= Cocoapods 점검 =========
if command -v pod >/dev/null 2>&1; then
  ok "CocoaPods 확인됨: $(pod --version)"
else
  warn "CocoaPods 감지 실패함. 'brew install cocoapods' 재시도 권장함"
fi

# ========= KDoctor 점검 =========
if command -v kdoctor >/dev/null 2>&1; then
  log "KDoctor 점검 실행함"
  kdoctor || true
  ok "KDoctor 보고서 출력 완료됨(경고 항목 참조 요망)"
else
  warn "KDoctor 실행 불가 상태임"
fi

# ========= 마무리 안내 =========
ok "설치 스크립트 완료됨"

cat <<'NOTE'

다음 작업 권장됨:
1) Xcode 설치 및 최초 실행 완료함(App Store 또는 `mas install 497799835`)
2) Android Studio 최초 실행 후 SDK Platform/Build-Tools 추가 설치함
3) 터미널 재시작 또는 `source ~/.zshrc`로 환경 반영함
4) 샘플 KMP 프로젝트 생성 및 빌드 검증 진행함
   - Android: Gradle Sync → 실행됨
   - iOS: XCFramework 생성 → SPM로 연결 또는 CocoaPods 연동됨

문제 발생 시:
- Android SDK 경로 점검: echo $ANDROID_SDK_ROOT 출력 확인함
- Xcode 초기화: sudo xcodebuild -runFirstLaunch 재실행함
- KDoctor 경고 항목 순서대로 해소함

NOTE