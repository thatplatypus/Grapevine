#!/usr/bin/env bash
# Runs the browser tests: the sample's page in headless Chromium, against containers of the image.
#   ./test-e2e.sh                                  build the image, then run every test
#   ./test-e2e.sh --filter-class "*CrossOrigin*"   extra arguments go to dotnet test
# Needs Docker and the .NET 10 SDK. The first run downloads Chromium for Playwright.
set -euo pipefail
cd "$(dirname "$0")"
docker build --platform linux/amd64 -t grapevine .
# From the project folder, so that its global.json selects the test runner.
cd tests/e2e
dotnet test "$@"
