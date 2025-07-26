#!/bin/bash

# Build and deploy Thread Flare debug container with variant support

set -e

IMAGE_NAME="thread-flare"
TAG="latest"
VARIANT="${1:-slim}"  # Default to slim, accept slim/cuda as argument

case "$VARIANT" in
    "slim")
        DOCKERFILE="Dockerfile.slim"
        FULL_IMAGE_NAME="${IMAGE_NAME}-slim:${TAG}"
        echo "Building Thread Flare SLIM container (CPU-only)..."
        ;;
    "cuda")
        DOCKERFILE="Dockerfile.cuda"
        FULL_IMAGE_NAME="${IMAGE_NAME}-cuda:${TAG}"
        echo "Building Thread Flare CUDA container (GPU-enabled)..."
        ;;
    *)
        echo "Usage: $0 [slim|cuda]"
        echo "  slim: CPU-only container (default)"
        echo "  cuda: GPU-enabled container with CUDA support"
        exit 1
        ;;
esac

docker build -f ${DOCKERFILE} -t ${FULL_IMAGE_NAME} .

echo "Thread Flare container built successfully!"
echo "Image: ${FULL_IMAGE_NAME}"
echo "Dockerfile: ${DOCKERFILE}"
echo ""
echo "To deploy to OpenShift/Kubernetes:"
echo "1. Update openshift-pod.yaml image to: ${FULL_IMAGE_NAME}"
echo "2. Apply pod: oc apply -f openshift-pod.yaml"
echo "3. Wait for ready: oc wait --for=condition=Ready pod/thread-flare --timeout=300s"
echo "4. View logs: oc logs -f pod/thread-flare"
echo ""
echo "To run locally:"
if [[ "$VARIANT" == "cuda" ]]; then
    echo "docker run --gpus all --rm -it ${FULL_IMAGE_NAME}"
else
    echo "docker run --rm -it ${FULL_IMAGE_NAME}"
fi
echo ""
echo "Available variants:"
echo "  ./build-and-deploy.sh slim   # CPU-only, smaller image"
echo "  ./build-and-deploy.sh cuda   # GPU-enabled, larger image"
