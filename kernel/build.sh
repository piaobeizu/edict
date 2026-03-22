#!/usr/bin/env bash
set -euo pipefail

# Build and publish Python package to PyPI
# Usage:
#   TWINE_USERNAME=__token__ TWINE_PASSWORD=pypi-xxx ./build.sh
#   TWINE_USERNAME=__token__ TWINE_PASSWORD=pypi-xxx ./build.sh --repository testpypi
#
# Optional args are passed through to `twine upload`.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "${ROOT_DIR}"

echo "[1/6] Cleaning old builds..."
rm -rf build dist *.egg-info

echo "[2/6] Ensuring build tools..."
python3 -m pip install --upgrade pip setuptools wheel build twine >/dev/null

echo "[3/6] Building package..."
sh gen_sha.sh
python3 -m build

echo "[4/6] install package force reinstall..."
python3 -m pip install --force-reinstall dist/*.whl

echo "[5/6] Uploading to PyPI..."
export TWINE_USERNAME="${TWINE_USERNAME:-__token__}"
: "${TWINE_PASSWORD:?TWINE_PASSWORD is required}"
python3 -m twine upload dist/* "$@"

echo "[6/6] cleaning up..."
unset TWINE_USERNAME
unset TWINE_PASSWORD

rm -rf build dist *.egg-info
echo "Done."

