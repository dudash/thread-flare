#!/bin/bash
# Thread Flare - Build and Dive Script
# Usage: ./build-and-dive.sh [slim|cuda] [optional: --tag <tag>]
# Builds the specified variant and opens it in dive for analysis.

set -e

VARIANT="slim"
TAG="latest"
POSITIONAL=()

usage() {
    echo "Usage: $0 [slim|cuda] [--tag <tag>]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        slim|cuda)
            VARIANT="$1"
            shift
            ;;
        --tag)
            TAG="$2"
            shift
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL[@]}"

if [[ "$VARIANT" == "slim" ]]; then
    DOCKERFILE="Dockerfile.slim"
    IMAGE_NAME="thread-flare-slim:${TAG}"
elif [[ "$VARIANT" == "cuda" ]]; then
    DOCKERFILE="Dockerfile.cuda"
    IMAGE_NAME="thread-flare-cuda:${TAG}"
else
    echo "Unknown variant: $VARIANT"
    usage
fi

echo "Building $IMAGE_NAME using $DOCKERFILE..."
docker build -f "$DOCKERFILE" -t "$IMAGE_NAME" .

echo "Launching dive for $IMAGE_NAME..."
dive "$IMAGE_NAME"
