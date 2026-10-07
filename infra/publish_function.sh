#!/usr/bin/env bash
# Package function_app/ with the grid_carbon package and deploy it to the Function App. Azure
# installs the requirements itself (remote build), so pymssql gets its Linux build.
#
#   infra/publish_function.sh

set -euo pipefail
cd "$(dirname "$0")/.."
source .env

BUILD=function_app/.build
rm -rf "$BUILD" && mkdir -p "$BUILD"
cp function_app/function_app.py function_app/host.json function_app/requirements.txt "$BUILD"/
cp -R src/grid_carbon "$BUILD"/grid_carbon
find "$BUILD" -name __pycache__ -prune -exec rm -rf {} +
(cd "$BUILD" && zip -qr ../app.zip .)

az functionapp deployment source config-zip -g "$AZURE_RESOURCE_GROUP" -n "$AZURE_FUNCTION_APP" \
  --src function_app/app.zip --build-remote true -o none
rm -rf "$BUILD" function_app/app.zip
echo "Deployed to $AZURE_FUNCTION_APP"
