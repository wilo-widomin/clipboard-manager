#!/usr/bin/env bash
# Build de Release + .dmg para distribución a usuarios de confianza.
#
# Uso:
#   ./scripts/build-release.sh                 # usa la versión del proyecto
#   ./scripts/build-release.sh 1.0.1           # marca la versión a 1.0.1
#
# Produce: dist/ClipboardManager-<version>.dmg
#
# Requiere:
#   - Cert "Apple Development" en el llavero.
#
# Firma MANUAL con el cert "Apple Development" del llavero. La app no usa
# sandbox ni capabilities que requieran perfil de aprovisionamiento, así que
# no hace falta cuenta de Apple ID configurada en Xcode ni notarización.
# Apto para repartir a usuarios de confianza (la primera vez deben abrir con
# clic derecho → Abrir, porque no está notarizada).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$REPO_ROOT/ClipboardManager.xcodeproj"
SCHEME="ClipboardManager"
CONFIG="Release"

# Team ID e identidad de firma. Si cambia de cuenta, sobrescribe con las
# variables de entorno DEVELOPMENT_TEAM / CODE_SIGN_IDENTITY.
# OJO: xcodebuild traduce el nombre "Apple Development" a "Mac Development" y
# no lo encuentra. Hay que pasar el hash SHA-1 exacto del cert del llavero
# (security find-identity -v -p codesigning).
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-7NZNHD46LC}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-6980741FE2CC5FAD224E24BBBABF5FE42E54A2F2}"

VERSION="${1:-}"

BUILD_DIR="$REPO_ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/ClipboardManager.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DIST_DIR="$REPO_ROOT/dist"

echo "==> Limpiando build/ y dist/"
rm -rf "$BUILD_DIR" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR" "$EXPORT_DIR"

# ---- Versión ----
if [[ -n "$VERSION" ]]; then
    echo "==> Marcando MARKETING_VERSION=$VERSION"
    VERSION_OVERRIDE=(MARKETING_VERSION="$VERSION")
else
    VERSION_OVERRIDE=()
fi

# ---- Archive (firma manual con cert Apple Development) ----
echo "==> Archive"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'generic/platform=macOS' \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    ${VERSION_OVERRIDE[@]+"${VERSION_OVERRIDE[@]}"} \
    archive

# ---- Extraer la .app del archive (ya viene firmada) ----
echo "==> Extrayendo la app del archive"
ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/ClipboardManager.app"
if [[ ! -d "$ARCHIVED_APP" ]]; then
    echo "ERROR: no se encontró $ARCHIVED_APP" >&2
    exit 1
fi
cp -R "$ARCHIVED_APP" "$EXPORT_DIR/"
APP_PATH="$EXPORT_DIR/ClipboardManager.app"

# ---- Verificar la firma ----
echo "==> Verificando firma"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --display --verbose=2 "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier" || true

# ---- Leer versión final si no se pasó por argumento ----
if [[ -z "$VERSION" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
        "$APP_PATH/Contents/Info.plist")
fi

DMG_PATH="$DIST_DIR/ClipboardManager-$VERSION.dmg"

# ---- Empaquetar DMG ----
echo "==> Empaquetando $DMG_PATH"
rm -f "$DMG_PATH"

DMG_STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP_PATH" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create \
    -volname "ClipboardManager $VERSION" \
    -srcfolder "$DMG_STAGE" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo ""
echo "==> Hecho"
echo "    App:  $APP_PATH"
echo "    DMG:  $DMG_PATH"
echo ""
echo "Pasos para repartirlo:"
echo "  1. Comparte $DMG_PATH con los usuarios."
echo "  2. Que arrastren ClipboardManager.app a Applications."
echo "  3. Primera vez: clic derecho sobre la app → Abrir → Abrir."