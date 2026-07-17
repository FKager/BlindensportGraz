#!/bin/bash
# One-time helper: exports your local "Apple Development" signing identity
# (certificate + private key) from the login keychain as a .p12 file, so it
# can be handed to the ios-device-deploy.yml GitHub Actions workflow as a
# self-contained CI signing identity (avoids the workflow ever touching your
# protected login keychain, which hits errSecInternalComponent when a
# non-interactive process tries to use it).
#
# Must be run in a real interactive Terminal, not through any automation —
# macOS will pop a Touch ID / password prompt to authorize the private key
# export, and only a genuine GUI session can show and answer that prompt.
#
# Usage:
#   ./download_certificate.sh [output_path]
#
# output_path defaults to ~/Desktop/BlindensportGraz-ci-cert.p12

set -euo pipefail

OUTPUT_PATH="${1:-$HOME/Desktop/BlindensportGraz-ci-cert.p12}"

if [ -e "$OUTPUT_PATH" ]; then
  read -r -p "$OUTPUT_PATH already exists. Overwrite? [y/N] " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
  fi
fi

echo "Choose a password for the exported .p12 file."
echo "(This is a new CI-only secret, NOT your Mac login password.)"
read -r -s -p "Password: " P12_PASSWORD
echo
read -r -s -p "Confirm password: " P12_PASSWORD_CONFIRM
echo

if [ "$P12_PASSWORD" != "$P12_PASSWORD_CONFIRM" ]; then
  echo "Passwords did not match. Aborted."
  exit 1
fi

if [ -z "$P12_PASSWORD" ]; then
  echo "Password cannot be empty. Aborted."
  exit 1
fi

echo "Exporting identities from the login keychain — approve the macOS prompt that appears..."
security export \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  -t identities \
  -f pkcs12 \
  -P "$P12_PASSWORD" \
  -o "$OUTPUT_PATH"

echo
echo "Done: $OUTPUT_PATH"
echo
echo "Next: tell Claude the output path and the password you just chose so it can"
echo "wire the certificate into the ios-device-deploy.yml workflow as a repo secret."
