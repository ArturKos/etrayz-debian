#!/bin/bash
# Launch the EtrayZ toolchain container interactively
#
# Usage:
#   ./toolchain/run.sh                    # interactive shell
#   ./toolchain/run.sh gcc -o hello hello.c  # run a single command

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Check if image exists
if ! docker image inspect etrayz-toolchain >/dev/null 2>&1; then
    echo "Docker image 'etrayz-toolchain' not found. Building it first..."
    "$SCRIPT_DIR/build.sh"
fi

if [ $# -eq 0 ]; then
    # Interactive mode — mount project root at /src
    exec docker run -it --rm \
        -v "$PROJECT_DIR:/src" \
        etrayz-toolchain
else
    # Command mode — run a command with the toolchain environment
    exec docker run --rm \
        -v "$PROJECT_DIR:/src" \
        etrayz-toolchain \
        "$@"
fi
