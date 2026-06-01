#!/usr/bin/env bash
# gpg-setup.sh — run once on your LOCAL machine before build-repo.sh
#
# Creates a GPG signing key for the APT repo.
# After running, copy the printed fingerprint into build-repo.sh as GPG_KEY_ID.

set -euo pipefail

GRN='\033[0;32m'; BLU='\033[0;34m'; RST='\033[0m'

echo -e "${BLU}Generating GPG key for APT repo signing...${RST}"
echo "  (choose RSA and RSA, 4096 bits, does not expire, name: LogLocate)"
echo ""

gpg --full-generate-key

echo ""
echo -e "${BLU}Your keys:${RST}"
gpg --list-keys --keyid-format LONG | grep -A1 "pub"

echo ""
echo -e "${GRN}Copy the fingerprint (long hex string) into build-repo.sh as GPG_KEY_ID${RST}"
echo "Then run: bash build-repo.sh"
