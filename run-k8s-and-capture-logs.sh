#!/bin/bash

# Thread Flare - OpenShift/Kubernetes Log Capture Script
# This script deploys Thread Flare to OpenShift/K8s and captures logs

set -e

# Usage/help
usage() {
    echo "Usage: $0 [--thread-limit N]"
    echo "  --thread-limit N: Limit the number of threads spawned inside the container"
    echo "  Set VARIANT=cuda for CUDA variant, NAMESPACE, TIMEOUT, etc. as env vars."
    exit 1
}

# Parse args
THREAD_LIMIT=""
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --thread-limit)
            THREAD_LIMIT="$2"
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

# Configuration
VARIANT="${VARIANT:-slim}"
NAMESPACE="${NAMESPACE:-default}"
POD_NAME="thread-flare"
LOG_DIR="./logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/thread_flare_k8s_${TIMESTAMP}.log"
SUMMARY_FILE="${LOG_DIR}/thread_flare_k8s_${TIMESTAMP}_summary.txt"
TIMEOUT="${TIMEOUT:-300}"
KUBE_CMD="${KUBE_CMD:-oc}"

# Determine image name based on variant
case "$VARIANT" in
    "slim")
        IMAGE_NAME="thread-flare-slim:latest"
        echo -e "${BLUE}Using Thread Flare SLIM (CPU-only) variant${NC}"
        ;;
    "cuda")
        IMAGE_NAME="thread-flare-cuda:latest"
        echo -e "${BLUE}Using Thread Flare CUDA (GPU-enabled) variant${NC}"
        ;;
    *)
        usage
        ;;
esac

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Thread Flare - K8s Log Capture Script${NC}"
echo "=============================================="

# Create logs directory if it doesn't exist
mkdir -p "${LOG_DIR}"

echo -e "${YELLOW}Configuration:${NC}"
echo "Pod name: ${POD_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "Timeout: ${TIMEOUT} seconds"
echo "Log file: ${LOG_FILE}"
echo "Summary file: ${SUMMARY_FILE}"
echo ""

# Check if oc/kubectl is available
if command -v oc >/dev/null 2>&1; then
    KUBE_CMD="oc"
    echo -e "${GREEN}Using OpenShift CLI (oc)${NC}"
elif command -v kubectl >/dev/null 2>&1; then
    KUBE_CMD="kubectl"
    echo -e "${GREEN}Using Kubernetes CLI (kubectl)${NC}"
else
    echo -e "${RED}Error: Neither 'oc' nor 'kubectl' found in PATH${NC}"
    echo "Please install OpenShift CLI or kubectl"
    exit 1
fi

# Check if pod YAML exists
if [ ! -f "pod-updated.yaml" ] && [ ! -f "pod.yaml" ]; then
    echo -e "${RED}Error: Pod YAML file not found${NC}"
    echo "Please run ./build-and-deploy.sh first to generate pod-updated.yaml"
    echo "Or ensure pod.yaml exists"
    exit 1
fi

# Determine which YAML file to use
if [ -f "pod-updated.yaml" ]; then
    POD_YAML="pod-updated.yaml"
else
    POD_YAML="pod.yaml"
fi

echo -e "${YELLOW}Using pod definition: ${POD_YAML}${NC}"

# Create log file header
cat > "${LOG_FILE}" << EOF
Thread Flare K8s Test Results
=======================================
Timestamp: $(date)
Host: $(hostname)
Kubernetes CLI: ${KUBE_CMD}
Namespace: ${NAMESPACE}
Pod YAML: ${POD_YAML}
Timeout: ${TIMEOUT} seconds

Deployment and Test Output:
--------------------------
EOF

# Function to cleanup pod
cleanup_pod() {
    echo -e "\n${YELLOW}Cleaning up pod...${NC}"
    ${KUBE_CMD} delete pod ${POD_NAME} -n ${NAMESPACE} --ignore-not-found=true >/dev/null 2>&1 || true
    echo "Pod cleanup completed"
}

# Set trap to cleanup on exit
trap cleanup_pod EXIT

# Deploy the pod
echo -e "${YELLOW}Deploying Thread Flare pod...${NC}"
${KUBE_CMD} apply -f "${POD_YAML}" -n "${NAMESPACE}" | tee -a "${LOG_FILE}"

# If thread limit is set, patch the env var
if [ -n "$THREAD_LIMIT" ]; then
    echo -e "${YELLOW}Setting THREAD_LIMIT to $THREAD_LIMIT in pod...${NC}"
    ${KUBE_CMD} set env pod/${POD_NAME} THREAD_LIMIT=${THREAD_LIMIT} -n "${NAMESPACE}" | tee -a "${LOG_FILE}"
fi

# Wait for pod to be ready
echo -e "${YELLOW}Waiting for pod to be ready...${NC}"
echo "Pod status:" | tee -a "${LOG_FILE}"

START_TIME=$(date +%s)
while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ $ELAPSED -gt $TIMEOUT ]; then
        echo -e "${RED}❌ Timeout waiting for pod to be ready${NC}"
        echo "Timeout after ${TIMEOUT} seconds" | tee -a "${LOG_FILE}"
        
        # Get pod status for debugging
        echo "Final pod status:" | tee -a "${LOG_FILE}"
        ${KUBE_CMD} get pod ${POD_NAME} -n ${NAMESPACE} -o wide | tee -a "${LOG_FILE}" 2>/dev/null || true
        echo "Pod events:" | tee -a "${LOG_FILE}"
        ${KUBE_CMD} get events --field-selector involvedObject.name=${POD_NAME} -n ${NAMESPACE} | tee -a "${LOG_FILE}" 2>/dev/null || true
        exit 1
    fi
    
    POD_STATUS=$(${KUBE_CMD} get pod ${POD_NAME} -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    echo "  $(date): Pod status: ${POD_STATUS}" | tee -a "${LOG_FILE}"
    
    if [ "$POD_STATUS" = "Running" ] || [ "$POD_STATUS" = "Succeeded" ]; then
        echo -e "${GREEN}✅ Pod is ready${NC}"
        break
    elif [ "$POD_STATUS" = "Failed" ]; then
        echo -e "${RED}❌ Pod failed${NC}"
        echo "Pod failed" | tee -a "${LOG_FILE}"
        exit 1
    fi
    
    sleep 5
done

# Capture logs
echo -e "${YELLOW}Capturing Thread Flare logs...${NC}"
echo "This may take a few minutes..."
echo ""
echo "Thread Flare execution logs:" | tee -a "${LOG_FILE}"
echo "============================" | tee -a "${LOG_FILE}"

# Follow logs until pod completes
if ${KUBE_CMD} logs -f ${POD_NAME} -n ${NAMESPACE} | tee -a "${LOG_FILE}"; then
    echo -e "\n${GREEN}✅ Thread Flare completed successfully!${NC}"
    EXIT_CODE=0
else
    echo -e "\n${RED}❌ Error capturing logs or pod failed${NC}"
    EXIT_CODE=1
fi

# Get final pod status
echo "" | tee -a "${LOG_FILE}"
echo "Final pod information:" | tee -a "${LOG_FILE}"
echo "=====================" | tee -a "${LOG_FILE}"
${KUBE_CMD} get pod ${POD_NAME} -n ${NAMESPACE} -o wide | tee -a "${LOG_FILE}" 2>/dev/null || true

# Add footer to log file
cat >> "${LOG_FILE}" << EOF

--------------------------
Test Completed: $(date)
Exit Code: ${EXIT_CODE}
EOF

# Generate summary
echo -e "${YELLOW}Generating summary...${NC}"

# Get consistent timestamp format
TIMESTAMP=$(date '+%a %b %d %H:%M:%S %Z %Y')

cat > "${SUMMARY_FILE}" << EOF
Thread Flare Test Summary (K8s)
====================================
Timestamp: ${TIMESTAMP}
Namespace: ${NAMESPACE}
Log File: ${LOG_FILE}
Exit Code: ${EXIT_CODE}

Key Metrics Extracted:
=====================
EOF

# Extract key metrics from the log
echo "Python Version:" >> "${SUMMARY_FILE}"
grep "Python version:" "${LOG_FILE}" | head -1 >> "${SUMMARY_FILE}" 2>/dev/null || echo "  Not found" >> "${SUMMARY_FILE}"

echo "" >> "${SUMMARY_FILE}"
echo "Cgroup/Process Limits:" >> "${SUMMARY_FILE}"
if ${KUBE_CMD} exec ${POD_NAME} -n ${NAMESPACE} -- test -f /sys/fs/cgroup/pids/pids.max 2>/dev/null; then
    echo "/sys/fs/cgroup/pids/pids.max:" >> "${SUMMARY_FILE}"
    ${KUBE_CMD} exec ${POD_NAME} -n ${NAMESPACE} -- cat /sys/fs/cgroup/pids/pids.max 2>/dev/null >> "${SUMMARY_FILE}"
fi
echo "/proc/self/limits (processes):" >> "${SUMMARY_FILE}"
${KUBE_CMD} exec ${POD_NAME} -n ${NAMESPACE} -- cat /proc/self/limits | grep processes 2>/dev/null >> "${SUMMARY_FILE}"

echo "" >> "${SUMMARY_FILE}"
echo "Test Status:" >> "${SUMMARY_FILE}"
grep -E "(Thread creation failed|Total threads spawned|Thread limit reached)" "${LOG_FILE}" >> "${SUMMARY_FILE}" 2>/dev/null || echo "  No thread creation failure detected" >> "${SUMMARY_FILE}"

echo "" >> "${SUMMARY_FILE}"
echo "Environment Detection:" >> "${SUMMARY_FILE}"
grep -E "(Container type|Kubernetes environment|Architecture|Platform)" "${LOG_FILE}" >> "${SUMMARY_FILE}" 2>/dev/null || echo "  Not found" >> "${SUMMARY_FILE}"

echo "" >> "${SUMMARY_FILE}"
echo "GPU Detection:" >> "${SUMMARY_FILE}"
grep -E "(nvidia-smi|GPU.*:|NVIDIA.*detected|GPU device files|Ray.*GPU)" "${LOG_FILE}" | head -10 >> "${SUMMARY_FILE}" 2>/dev/null || echo "  No GPU information found" >> "${SUMMARY_FILE}"

echo "" >> "${SUMMARY_FILE}"
echo "Cgroup Detection:" >> "${SUMMARY_FILE}"
grep -E "(No cgroup.*found|cgroup.*mount|cgroup.*pids\.max|cgroup.*memory)" "${LOG_FILE}" | head -5 >> "${SUMMARY_FILE}" 2>/dev/null || echo "  Not found" >> "${SUMMARY_FILE}"

echo "" >> "${SUMMARY_FILE}"
echo "Ray Resources:" >> "${SUMMARY_FILE}"
grep -E "(Ray detected|Cluster resource|Memory comparison|CPU comparison)" "${LOG_FILE}" | head -10 >> "${SUMMARY_FILE}" 2>/dev/null || echo "  Not found" >> "${SUMMARY_FILE}"

echo "" >> "${SUMMARY_FILE}"
echo "Thread Test Results:" >> "${SUMMARY_FILE}"
LAST_THREAD_COUNT=$(grep "Created.*threads" "${LOG_FILE}" | tail -1 2>/dev/null || echo "")
THREAD_FAILURE=$(grep "Thread creation failed" "${LOG_FILE}" 2>/dev/null || echo "")
if [ -n "$LAST_THREAD_COUNT" ]; then
    echo "  $LAST_THREAD_COUNT" >> "${SUMMARY_FILE}"
fi
if [ -n "$THREAD_FAILURE" ]; then
    echo "  $THREAD_FAILURE" >> "${SUMMARY_FILE}"
else
    echo "  No thread creation failure detected" >> "${SUMMARY_FILE}"
fi

# Check for warnings and errors
echo "" >> "${SUMMARY_FILE}"
echo "Warnings and Errors:" >> "${SUMMARY_FILE}"
WARNINGS=$(grep -i "warning\|error" "${LOG_FILE}" 2>/dev/null || echo "")
if [ -n "$WARNINGS" ]; then
    echo "$WARNINGS" | head -5 >> "${SUMMARY_FILE}"
else
    echo "  No warnings or errors detected" >> "${SUMMARY_FILE}"
fi

echo "" >> "${SUMMARY_FILE}"
echo "Kubernetes Environment:" >> "${SUMMARY_FILE}"
echo "  CLI: ${KUBE_CMD}" >> "${SUMMARY_FILE}"
echo "  Namespace: ${NAMESPACE}" >> "${SUMMARY_FILE}"

echo "" >> "${SUMMARY_FILE}"
echo "Test Status:" >> "${SUMMARY_FILE}"
if [ $EXIT_CODE -eq 0 ]; then
    echo "  ✅ All tests completed successfully" >> "${SUMMARY_FILE}"
else
    echo "  ❌ Tests failed or were interrupted" >> "${SUMMARY_FILE}"
fi

# Show summary
echo ""
echo -e "${BLUE}Summary:${NC}"
cat "${SUMMARY_FILE}"

echo ""
echo -e "${GREEN}Files created:${NC}"
echo "  📄 Full log: ${LOG_FILE}"
echo "  📋 Summary: ${SUMMARY_FILE}"

# Calculate file sizes
LOG_SIZE=$(du -h "${LOG_FILE}" | cut -f1)
SUMMARY_SIZE=$(du -h "${SUMMARY_FILE}" | cut -f1)

echo ""
echo -e "${BLUE}File sizes:${NC}"
echo "  Full log: ${LOG_SIZE}"
echo "  Summary: ${SUMMARY_SIZE}"

echo ""
echo -e "${YELLOW}To view logs:${NC}"
echo "  cat ${LOG_FILE}"
echo "  less ${LOG_FILE}"
echo ""
echo -e "${YELLOW}To view summary:${NC}"
echo "  cat ${SUMMARY_FILE}"

exit $EXIT_CODE
