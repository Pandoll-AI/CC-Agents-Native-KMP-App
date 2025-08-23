#!/bin/zsh
# KMP App Builder — Safe Installer (no VS Code)
# - Idempotent: skips packages already installed
# - Safe: prints warnings instead of failing hard on optional steps
# - Scope: toolchain + Claude agent/command placement only (no IDE install)
#
# Usage:
#   bash kmpsetup.safe.sh
#   zsh  kmpsetup.safe.sh
#
# Optional env:
#   SRC_DIR=/path/to/repo   # defaults to this script's directory

set -euo pipefail

# ------------- utils -------------
log()  { printf "\n[INFO] %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*"; }
ok()   { printf "\n[OK]  %s\n" "$*"; }
die()  { printf "\n[ERR]  %s\n" "$*" >&2; exit 1; }

append_if_absent() {
  # $1=file, $2=line
  local f="$1"; local line="$2"
  mkdir -p "$(dirname "$f")"
  touch "$f"
  if ! grep -Fqx "$line" "$f" 2>/dev/null; then
    echo "$line" >> "$f"
  fi
}

# capture failures with last command
trap 'warn "A step failed. Last command may have errored. You can re-run safely."' ERR

# ------------- paths -------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${0:A}")" && pwd)"
SRC_DIR="${SRC_DIR:-$SCRIPT_DIR}"

CLAUDE_HOME="${HOME}/.claude"
AGENTS_DIR="${CLAUDE_HOME}/agents"
CMDS_DIR="${CLAUDE_HOME}/commands"
STATE_DIR="${CLAUDE_HOME}/state"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

# ------------- preflight -------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  warn "This script is tuned for macOS. Proceeding anyway."
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  warn "Apple Silicon optimisations may not apply on your CPU ($(uname -m))."
fi

# ------------- Homebrew -------------
if ! command -v brew >/dev/null 2>&1; then
  log "Homebrew not found. Installing non-interactively..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # shellenv
  if [[ -x /opt/homebrew/bin/brew ]]; then
    append_if_absent "$ZSHRC" 'eval "$(/opt/homebrew/bin/brew shellenv)"'
    eval "$(/opt/homebrew/bin/brew shellenv)"
    ok "Homebrew installed and initialised"
  else
    die "Homebrew install appears incomplete. Please check the installer output."
  fi
else
  ok "Homebrew already installed"
fi

log "brew update (safe)"
brew update || warn "brew update failed; continuing"

# ------------- required CLI/toolchain -------------
# We intentionally do NOT install VS Code.
BREW_FORMULAE=(git gradle openjdk kotlin cocoapods)
for pkg in "${BREW_FORMULAE[@]}"; do
  if brew list "$pkg" >/dev/null 2>&1; then
    ok "$pkg already installed"
  else
    log "Installing $pkg"
    brew install "$pkg" || die "Failed to install $pkg"
  fi
done

# Java toolchain export (for shells after reboot as well)
if [[ -d "$(/usr/libexec/java_home 2>/dev/null)" ]]; then
  JAVA_HOME_SET='export JAVA_HOME="$(/usr/libexec/java_home)"'
  append_if_absent "$ZSHRC" "$JAVA_HOME_SET"
  eval "$JAVA_HOME_SET"
  ok "JAVA_HOME configured"
fi

# ------------- Xcode toolchain checks -------------
if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode Command Line Tools present"
else
  warn "Xcode CLT not detected. Run: xcode-select --install"
fi

# Attempt to accept license non-interactively (best-effort)
if /usr/bin/sudo -n xcodebuild -license accept 2>/dev/null; then
  ok "Xcode license accepted (non-interactive)"
else
  warn "Could not accept Xcode license non-interactively. You may need: sudo xcodebuild -license"
fi

# ------------- Android SDK (best-effort) -------------
if command -v sdkmanager >/dev/null 2>&1; then
  ok "Android SDK tools detected"
else
  warn "Android commandline tools not found. Install Android Studio or sdkmanager for full KMP Android builds."
fi

# ------------- Claude agents/commands placement -------------
log "Placing Claude agents & commands"
mkdir -p "$AGENTS_DIR" "$CMDS_DIR" "$STATE_DIR"

# KMP bundle lives under agents/kmp-app-builder in the repo
if [[ -d "$SRC_DIR/agents" ]]; then
  rsync -a --delete "$SRC_DIR/agents/" "$AGENTS_DIR/" 2>/dev/null || cp -R "$SRC_DIR/agents/." "$AGENTS_DIR/"
  ok "Agents synced to $AGENTS_DIR"
else
  warn "No agents/ directory found under $SRC_DIR; skipping agents copy"
fi

if [[ -d "$SRC_DIR/commands" ]]; then
  rsync -a --delete "$SRC_DIR/commands/" "$CMDS_DIR/" 2>/dev/null || cp -R "$SRC_DIR/commands/." "$CMDS_DIR/"
  ok "Commands synced to $CMDS_DIR"
else
  warn "No commands/ directory found under $SRC_DIR; skipping commands copy"
fi

# Ensure main setup script is executable if it was copied into Claude dir
if [[ -f "$AGENTS_DIR/kmp-app-builder/kmpsetup.sh" ]]; then
  chmod +x "$AGENTS_DIR/kmp-app-builder/kmpsetup.sh" || true
  ok "Marked kmpsetup.sh executable"
fi

# ------------- optional: claude alias bootstrap (safe) -------------
# If you want a claude CLI alias, detect the binary and set it.
if command -v claude >/dev/null 2>&1; then
  ok "claude CLI detected at: $(which claude)"
else
  warn "claude CLI not found in PATH. If installed via npm, add its path to your shell."
fi

# ------------- state & preferences -------------
append_if_absent "${STATE_DIR}/kmp-preferences.json" "{}"
ok "Preferences placeholder ensured at ${STATE_DIR}/kmp-preferences.json"

# ------------- summary -------------
cat <<SUMMARY

============================================
 KMP App Builder — Setup Summary (Safe Mode)
============================================
Homebrew .......... $(brew --version | head -n1 2>/dev/null || echo "not found")
Git ............... $(git --version 2>/dev/null || echo "not found")
Gradle ............ $(gradle --version 2>/dev/null | head -n1 || echo "not found")
Java (JAVA_HOME)... ${JAVA_HOME:-"(not set)"}
Kotlin ............ $(kotlin -version 2>&1 | head -n1 || echo "not found")
CocoaPods ......... $(pod --version 2>/dev/null || echo "not found")
Xcode-select ...... $(xcode-select -p 2>/dev/null || echo "not found")
Android sdkmanager  $(command -v sdkmanager >/dev/null 2>&1 && echo "found" || echo "not found")

Claude agents dir . $AGENTS_DIR
Claude cmds dir ... $CMDS_DIR

Next steps:
- In Claude Code, try: /kmp or /kmp-nl
- For Android builds, ensure Android SDK + platform tools are installed.
- If Xcode license prompts occur, run: sudo xcodebuild -license
============================================
SUMMARY

ok "Setup completed (safe, idempotent, no VS Code install)."
