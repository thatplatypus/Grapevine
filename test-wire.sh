#!/usr/bin/env bash
# Runs the wire-level tests: real sockets against containers of the image.
#   ./test-wire.sh                               build the image, then run every test
#   ./test-wire.sh --filter-class "*SoakTests"   extra arguments go to dotnet test
# Needs Docker and the .NET 10 SDK. Testcontainers pulls one small helper image the first time.
set -euo pipefail
cd "$(dirname "$0")"
docker build --platform linux/amd64 -t grapevine .
# From the project folder, so that its global.json selects the test runner.
cd tests/wire
dotnet test "$@"
