#!/bin/bash
# Thread Flare - Build and Load into kind Script
# Usage: ./build-and-load-kind.sh [slim|cuda] [optional: --tag <tag>] [optional: --kind-cluster <name>]
# Builds the specified variant and loads it into the specified kind cluster.

set -e

VARIANT="slim"
TAG="latest"
KIND_CLUSTER="kind"
POSITIONAL=()

usage() {
    echo "Usage: $0 [slim|cuda] [--tag <tag>] [--kind-cluster <name>]"
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
        --kind-cluster)
            KIND_CLUSTER="$2"
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

echo "Loading $IMAGE_NAME into kind cluster '$KIND_CLUSTER'..."
kind load docker-image "$IMAGE_NAME" --name "$KIND_CLUSTER"

echo "Image $IMAGE_NAME loaded into kind cluster '$KIND_CLUSTER'."
