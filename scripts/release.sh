#!/bin/zsh
# FootswitchController を Release ビルド → 署名 → 公証 → staple → DMG 化するスクリプト。
#
# 事前準備 (一度だけ):
#   1. appleid.apple.com で app 用パスワードを生成
#   2. keychain に認証情報を保存:
#      xcrun notarytool store-credentials "footswitch-notary" \
#        --apple-id "<あなたのApple ID>" --team-id N957X4L8PY --password "<app用パスワード>"
#
# 使い方:
#   ./scripts/release.sh [keychain-profile-name]
#   (profile 名を省略すると footswitch-notary を使う)

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="FootswitchController"
TEAM_ID="N957X4L8PY"
SIGN_ID="Developer ID Application: Yoshiharu Sato (${TEAM_ID})"
PROFILE="${1:-footswitch-notary}"
BUILD_DIR="build"
DIST_DIR="dist"
APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
ZIP_PATH="${DIST_DIR}/${APP_NAME}.zip"
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"

echo "==> [1/6] xcodegen generate"
xcodegen generate >/dev/null

# 公証 submit して Accepted を確認する。Invalid ならログを出して中断。
notarize() {
  local target="$1"
  local out
  out=$(xcrun notarytool submit "${target}" --keychain-profile "${PROFILE}" --wait 2>&1)
  echo "${out}"
  if ! echo "${out}" | grep -q "status: Accepted"; then
    local subid
    subid=$(echo "${out}" | grep -m1 "id:" | awk '{print $2}')
    echo "!! 公証が Accepted になりませんでした。詳細ログ:"
    [ -n "${subid}" ] && xcrun notarytool log "${subid}" --keychain-profile "${PROFILE}"
    exit 1
  fi
}

echo "==> [2/6] Release ビルド (Developer ID 署名 + Hardened Runtime + secure timestamp)"
# OTHER_CODE_SIGN_FLAGS=--timestamp: secure timestamp を付与 (公証必須)
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO: get-task-allow (debug 用) を付けない
xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" \
  -configuration Release -derivedDataPath "${BUILD_DIR}" \
  CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=${SIGN_ID}" \
  PROVISIONING_PROFILE_SPECIFIER="" DEVELOPMENT_TEAM="${TEAM_ID}" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build >/dev/null

mkdir -p "${DIST_DIR}"

echo "==> [3/6] .app を zip 化して公証"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"
notarize "${ZIP_PATH}"

echo "==> [4/6] .app に公証チケットを staple"
xcrun stapler staple "${APP_PATH}"

echo "==> [5/6] DMG 作成 (Applications へのシンボリックリンク同梱)"
STAGING=$(mktemp -d)
cp -R "${APP_PATH}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"
rm -f "${DMG_PATH}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING}" -ov -format UDZO "${DMG_PATH}" >/dev/null
rm -rf "${STAGING}"
codesign --force --sign "${SIGN_ID}" "${DMG_PATH}"

echo "==> [6/6] DMG を公証して staple"
notarize "${DMG_PATH}"
xcrun stapler staple "${DMG_PATH}"

echo ""
echo "完了: ${DMG_PATH}"
echo "検証:"
spctl -a -t open --context context:primary-signature -v "${DMG_PATH}" || true
xcrun stapler validate "${DMG_PATH}" || true
