#!/usr/bin/env bash
#
# コマンドラインから TestApp をビルド / テストするスクリプト。
#
# 使い方:
#   scripts/build.sh            # macOS と iOS Simulator 向けにビルド
#   scripts/build.sh macos      # macOS 向けのみビルド
#   scripts/build.sh ios        # iOS Simulator 向けのみビルド
#   scripts/build.sh test       # iOS Simulator でユニットテストを実行
#
# 環境変数:
#   SIMULATOR   テストやビルドに使うシミュレーター名 (既定: "iPhone 17")
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/TestApp.xcodeproj"
SCHEME="TestApp"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
SIMULATOR="${SIMULATOR:-iPhone 17}"

# xcode-select が Command Line Tools を指していても Xcode.app を使う
if ! xcodebuild -version >/dev/null 2>&1; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

run_xcodebuild() {
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -derivedDataPath "$DERIVED_DATA" \
        "$@"
}

build_macos() {
    echo "==> Building for macOS"
    run_xcodebuild -destination "platform=macOS" build
}

build_ios() {
    echo "==> Building for iOS Simulator ($SIMULATOR)"
    run_xcodebuild -destination "platform=iOS Simulator,name=$SIMULATOR" build
}

run_tests() {
    echo "==> Testing on iOS Simulator ($SIMULATOR)"
    run_xcodebuild -destination "platform=iOS Simulator,name=$SIMULATOR" test
}

case "${1:-all}" in
    macos) build_macos ;;
    ios)   build_ios ;;
    test)  run_tests ;;
    all)   build_macos; build_ios ;;
    *)
        echo "Unknown command: $1" >&2
        echo "Usage: $0 [all|macos|ios|test]" >&2
        exit 1
        ;;
esac
