#!/usr/bin/env bash
# Install "MS Classic Is Up" into ~/Applications by building it from source.
#
#   curl -fsSL https://raw.githubusercontent.com/Yozez/ms-classic-is-up/main/install.sh | bash
#
# Run from inside a checkout (./install.sh) to build that checkout instead of cloning.
#
# Everything runs inside main(), which is only called on the last line, so a partially
# downloaded script (e.g. a dropped connection during `curl | bash`) does nothing.
set -euo pipefail

main() {
  local repo_url="https://github.com/Yozez/ms-classic-is-up.git"
  local app_name="MS Classic Is Up"
  local bundle_id="com.yozez.ms-classic-is-up"
  local install_dir="${INSTALL_DIR:-$HOME/Applications}"

  say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
  fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

  [[ "$(uname -s)" == "Darwin" ]] || fail "This app only runs on macOS."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  (( major >= 14 )) || fail "macOS 14 (Sonoma) or later is required (found $(sw_vers -productVersion))."
  [[ "$install_dir" == /* ]] || fail "INSTALL_DIR must be an absolute path (got '$install_dir')."

  if ! command -v swift >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    fail "Swift and git are required. Install Apple's Command Line Tools with:  xcode-select --install"
  fi

  # Use the current checkout if we're inside one, otherwise clone into a private temp dir.
  local script_dir="" src
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi
  if [[ -n "$script_dir" && -f "$script_dir/Package.swift" && -f "$script_dir/scripts/build-app.sh" ]]; then
    src="$script_dir"
  else
    WORK_DIR="$(mktemp -d)"
    trap 'rm -rf -- "$WORK_DIR"' EXIT
    say "Downloading source..."
    git clone --quiet --depth 1 "$repo_url" "$WORK_DIR/src"
    src="$WORK_DIR/src"
  fi

  say "Building (first build takes about a minute)..."
  "$src/scripts/build-app.sh" >/dev/null

  local target="$install_dir/$app_name.app"
  say "Installing to ${install_dir}..."
  pkill -x MSClassicTray 2>/dev/null || true
  mkdir -p "$install_dir"
  if [[ -e "$target" || -L "$target" ]]; then
    # Only ever replace our own app bundle.
    local existing_id
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist" 2>/dev/null || true)"
    [[ ! -L "$target" && "$existing_id" == "$bundle_id" ]] \
      || fail "'$target' exists but isn't this app; not touching it."
    rm -rf -- "$target"
  fi
  cp -R "$src/build/$app_name.app" "$install_dir/"

  # LaunchServices can briefly refuse to open an app that was just quit; retry once.
  open "$target" 2>/dev/null || { sleep 2; open "$target"; }
  say "Done! Look for the maple leaf in your menu bar."
  say "Tip: enable 'Launch at login' from its menu."
}

main "$@"
