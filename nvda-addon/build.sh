#!/bin/zsh
# Packs the add-on as excelCheckboxes-<version>.nvda-addon next to this script.
set -euo pipefail
cd "$(dirname "$0")"
python3 tests/test_checkboxState.py
version=$(awk '$1 == "version" {print $3}' excelCheckboxes/manifest.ini)
output=$PWD/excelCheckboxes-$version.nvda-addon
rm -f "$output"
cd excelCheckboxes
zip -qr -X "$output" manifest.ini globalPlugins -x '*__pycache__*'
echo "$output"
