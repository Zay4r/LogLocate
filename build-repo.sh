#!/usr/bin/env bash
# build-repo.sh
#
# Builds loglo.deb, generates APT repo metadata, signs with GPG.
# Output goes to ./docs/ — push to GitHub and enable Pages on that folder.
#
# Run on your LOCAL machine (not the server):
#   bash build-repo.sh
#
# First-time GPG setup (run once):
#   gpg --full-generate-key          # choose RSA 4096, no expiry
#   gpg --list-keys                  # note the key fingerprint
#   gpg --armor --export <fingerprint> > docs/KEY.gpg
#   # Set GPG_KEY_ID below to your fingerprint

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
PACKAGE="loglo"
VERSION="1.0.0"
ARCH="all"
GPG_KEY_ID="61696B2AE401ACA032BA0785530FC99235C96A47"
REPO_ORIGIN="LogLocate"
REPO_LABEL="loglo"
SUITE="stable"
COMPONENT="main"

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/deb-build"
DEB_NAME="${PACKAGE}_${VERSION}.deb"
DOCS_DIR="${SCRIPT_DIR}/docs"
POOL_DIR="${DOCS_DIR}/pool/${COMPONENT}"
DISTS_DIR="${DOCS_DIR}/dists/${SUITE}/${COMPONENT}/binary-${ARCH}"

RED='\033[0;31m'; GRN='\033[0;32m'; BLU='\033[0;34m'; RST='\033[0m'

# ── Check deps ────────────────────────────────────────────────────────────────
for dep in dpkg-deb dpkg-scanpackages apt-ftparchive gpg gzip; do
  command -v "$dep" &>/dev/null || { echo -e "${RED}Missing: $dep${RST}" >&2; exit 1; }
done

echo -e "${BLU}Building ${PACKAGE} v${VERSION}...${RST}"

# ── Build .deb ────────────────────────────────────────────────────────────────
mkdir -p "${BUILD_DIR}/${PACKAGE}_${VERSION}/DEBIAN"
mkdir -p "${BUILD_DIR}/${PACKAGE}_${VERSION}/usr/local/bin"
mkdir -p "${BUILD_DIR}/${PACKAGE}_${VERSION}/etc/log-locate"
mkdir -p "${BUILD_DIR}/${PACKAGE}_${VERSION}/etc/systemd/system"

# Copy files into package layout
cp "${SCRIPT_DIR}/log-locate"          "${BUILD_DIR}/${PACKAGE}_${VERSION}/usr/local/bin/log-locate"
cp "${SCRIPT_DIR}/log-locate-daemon"   "${BUILD_DIR}/${PACKAGE}_${VERSION}/usr/local/bin/log-locate-daemon"
cp "${SCRIPT_DIR}/config"              "${BUILD_DIR}/${PACKAGE}_${VERSION}/etc/log-locate/config"
cp "${SCRIPT_DIR}/log-locate_.service" "${BUILD_DIR}/${PACKAGE}_${VERSION}/etc/systemd/system/log-locate_.service"

# DEBIAN control files
cat > "${BUILD_DIR}/${PACKAGE}_${VERSION}/DEBIAN/control" << CTRL
Package: ${PACKAGE}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Depends: bash, curl, coreutils, systemd, gawk
Maintainer: Zay4r <your@email.com>
Homepage: https://github.com/Zay4r/LogLocate
Description: Log indexer and alerter
 loglo watches log files, indexes matching tokens into a fast .idx file,
 and sends Telegram or email alerts when alert patterns are matched.
CTRL

cp "${SCRIPT_DIR}/DEBIAN/postinst" "${BUILD_DIR}/${PACKAGE}_${VERSION}/DEBIAN/postinst"
cp "${SCRIPT_DIR}/DEBIAN/prerm"    "${BUILD_DIR}/${PACKAGE}_${VERSION}/DEBIAN/prerm"

chmod 755 "${BUILD_DIR}/${PACKAGE}_${VERSION}/usr/local/bin/log-locate"
chmod 755 "${BUILD_DIR}/${PACKAGE}_${VERSION}/usr/local/bin/log-locate-daemon"
chmod 755 "${BUILD_DIR}/${PACKAGE}_${VERSION}/DEBIAN/postinst"
chmod 755 "${BUILD_DIR}/${PACKAGE}_${VERSION}/DEBIAN/prerm"
chmod 644 "${BUILD_DIR}/${PACKAGE}_${VERSION}/etc/log-locate/config"
chmod 644 "${BUILD_DIR}/${PACKAGE}_${VERSION}/etc/systemd/system/log-locate_.service"

# Build in /tmp (Linux filesystem) to avoid Windows/WSL 777 permission errors
TMP_BUILD="/tmp/${PACKAGE}_${VERSION}_build"
rm -rf "$TMP_BUILD"
cp -a "${BUILD_DIR}/${PACKAGE}_${VERSION}" "$TMP_BUILD"
chmod 755 "$TMP_BUILD/DEBIAN"
chmod 755 "$TMP_BUILD/DEBIAN/postinst"
chmod 755 "$TMP_BUILD/DEBIAN/prerm"
dpkg-deb --build "$TMP_BUILD" "${BUILD_DIR}/${DEB_NAME}"
rm -rf "$TMP_BUILD"
echo -e "${GRN}  Built: ${BUILD_DIR}/${DEB_NAME}${RST}"

# ── Populate APT repo pool ─────────────────────────────────────────────────────
mkdir -p "$POOL_DIR"
mkdir -p "$DISTS_DIR"
cp "${BUILD_DIR}/${DEB_NAME}" "${POOL_DIR}/${DEB_NAME}"

# ── Generate Packages index ───────────────────────────────────────────────────
cd "$DOCS_DIR"
dpkg-scanpackages --arch "$ARCH" "pool/${COMPONENT}" /dev/null > "${DISTS_DIR}/Packages"
gzip -k -f "${DISTS_DIR}/Packages"
echo -e "${GRN}  Generated: Packages + Packages.gz${RST}"

# ── Generate Release file ─────────────────────────────────────────────────────
RELEASE_FILE="${DOCS_DIR}/dists/${SUITE}/Release"
apt-ftparchive \
  -o "APT::FTPArchive::Release::Origin=${REPO_ORIGIN}" \
  -o "APT::FTPArchive::Release::Label=${REPO_LABEL}" \
  -o "APT::FTPArchive::Release::Suite=${SUITE}" \
  -o "APT::FTPArchive::Release::Codename=${SUITE}" \
  -o "APT::FTPArchive::Release::Components=${COMPONENT}" \
  -o "APT::FTPArchive::Release::Architectures=${ARCH}" \
  release "${DOCS_DIR}/dists/${SUITE}" > "$RELEASE_FILE"
echo -e "${GRN}  Generated: Release${RST}"

# ── Sign Release ──────────────────────────────────────────────────────────────
if [[ -z "$GPG_KEY_ID" ]]; then
  echo -e "\033[1;33m  Warning: GPG_KEY_ID not set — skipping signing.\033[0m"
  echo -e "\033[1;33m  Set GPG_KEY_ID in this script and re-run to enable signed releases.\033[0m"
else
  gpg --default-key "$GPG_KEY_ID" \
    --armor --detach-sign \
    --output "${DOCS_DIR}/dists/${SUITE}/Release.gpg" \
    "$RELEASE_FILE"

  gpg --default-key "$GPG_KEY_ID" \
    --armor --clearsign \
    --output "${DOCS_DIR}/dists/${SUITE}/InRelease" \
    "$RELEASE_FILE"

  # Export public key for users to trust
  gpg --armor --export "$GPG_KEY_ID" > "${DOCS_DIR}/KEY.gpg"
  echo -e "${GRN}  Signed: Release.gpg + InRelease${RST}"
  echo -e "${GRN}  Exported: docs/KEY.gpg${RST}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GRN}APT repo built in ./docs/${RST}"
echo ""
echo "Next:"
echo "  git add docs/"
echo "  git commit -m \"Release v${VERSION}\""
echo "  git push origin main"
echo ""
echo "Users install with:"
echo "  curl -fsSL https://zay4r.github.io/LogLocate/KEY.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/loglo.gpg"
echo "  echo \"deb [signed-by=/etc/apt/keyrings/loglo.gpg] https://zay4r.github.io/LogLocate stable main\" | sudo tee /etc/apt/sources.list.d/loglo.list"
echo "  sudo apt update && sudo apt install loglo"
echo ""