#!/bin/bash

# Thread Flare - Run and Capture Logs Script
# This script runs the Thread Flare container and captures all output to timestamped log files

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage/help
usage() {
    echo "Usage: $0 [slim|cuda] [--thread-limit N]"
    echo "  slim: CPU-only container (default)"
    echo "  cuda: GPU-enabled container with CUDA support"
    echo "  --thread-limit N: Limit the number of threads spawned inside the container"
    exit 1
}

# Parse args
VARIANT="slim"
THREAD_LIMIT=""
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        slim|cuda)
            VARIANT="$1"
            shift
            ;;
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

case "$VARIANT" in
    "slim")
        IMAGE_NAME="thread-flare-slim:latest"
        DOCKER_ARGS="--rm"
        echo -e "${BLUE}Using Thread Flare SLIM (CPU-only) variant${NC}"
        ;;
    "cuda")
        IMAGE_NAME="thread-flare-cuda:latest"
        DOCKER_ARGS="--gpus all --rm"
        echo -e "${BLUE}Using Thread Flare CUDA (GPU-enabled) variant${NC}"
        ;;
    *)
        usage
        ;;
esac

LOG_DIR="./logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/thread_flare_${TIMESTAMP}.log"
SUMMARY_FILE="${LOG_DIR}/thread_flare_${TIMESTAMP}_summary.txt"

echo -e "${BLUE}Thread Flare - Log Capture Script${NC}"
echo "=================================="

# Create logs directory if it doesn't exist
mkdir -p "${LOG_DIR}"

echo -e "${YELLOW}Starting Thread Flare container...${NC}"
echo "Timestamp: $(date)"
echo "Log file: ${LOG_FILE}"
echo "Summary file: ${SUMMARY_FILE}"
echo ""

# Check if image exists
if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    echo -e "${RED}Error: Docker image '${IMAGE_NAME}' not found.${NC}"
    echo "Please build the image first with: docker build -t thread-flare:latest ."
    exit 1
fi

# Run container and capture logs
echo -e "${YELLOW}Running Thread Flare and capturing logs...${NC}"
echo "This may take a few minutes depending on thread limit testing..."
echo ""

# Create log file header
cat > "${LOG_FILE}" << EOF
Thread Flare Test Results
========================
Timestamp: $(date)
Host: $(hostname)
Docker Version: $(docker --version)
Image: ${IMAGE_NAME}

Test Output:
-----------
EOF

# Run the container and capture output
DOCKER_ENV_ARGS=""
DOCKER_CLI_ARG=""
if [ -n "$THREAD_LIMIT" ]; then
    DOCKER_ENV_ARGS="-e THREAD_LIMIT=$THREAD_LIMIT"
    DOCKER_CLI_ARG="--thread-limit $THREAD_LIMIT"
    echo -e "${YELLOW}Thread limit set to: $THREAD_LIMIT${NC}"
fi
if docker run ${DOCKER_ARGS} $DOCKER_ENV_ARGS "${IMAGE_NAME}" $DOCKER_CLI_ARG 2>&1 | tee -a "${LOG_FILE}"; then
    echo -e "\n${GREEN}✅ Thread Flare completed successfully!${NC}"
    EXIT_CODE=0
else
    echo -e "\n${RED}❌ Thread Flare failed or was interrupted.${NC}"
    EXIT_CODE=1
fi

# Add footer to log file
cat >> "${LOG_FILE}" << EOF

-----------
Test Completed: $(date)
Exit Code: ${EXIT_CODE}
EOF


# Generate summary
echo -e "${YELLOW}Generating summary...${NC}"

# Get consistent timestamp format
TIMESTAMP=$(date '+%a %b %d %H:%M:%S %Z %Y')

cat > "${SUMMARY_FILE}" << EOF
Thread Flare Test Summary
========================
Timestamp: ${TIMESTAMP}
Log File: ${LOG_FILE}
Exit Code: ${EXIT_CODE}

Key Metrics Extracted:
=====================
EOF

# Extract key metrics from the log
echo "Python Version:" >> "${SUMMARY_FILE}"
grep "Python version:" "${LOG_FILE}" | head -1 >> "${SUMMARY_FILE}" 2>/dev/null || echo "  Not found" >> "${SUMMARY_FILE}"

echo "" >> "${SUMMARY_FILE}"
echo "" >> "${SUMMARY_FILE}"
echo "Test Status:" >> "${SUMMARY_FILE}"
grep -E "(Thread creation failed|Total threads spawned|Thread limit reached)" "${LOG_FILE}" >> "${SUMMARY_FILE}" 2>/dev/null || echo "  No thread creation failure detected" >> "${SUMMARY_FILE}"

echo "" >> "${SUMMARY_FILE}"
echo "Environment Detection:" >> "${SUMMARY_FILE}"
grep -E "(Container type|Kubernetes environment|Architecture|Platform)" "${LOG_FILE}" >> "${SUMMARY_FILE}" 2>/dev/null || echo "  Not found" >> "${SUMMARY_FILE}"

echo "" >> "${SUMMARY_FILE}"
echo "System Resources:" >> "${SUMMARY_FILE}"
grep -E "(CPU cores|Memory total|Memory available|Memory used)" "${LOG_FILE}" >> "${SUMMARY_FILE}" 2>/dev/null || echo "  Not found" >> "${SUMMARY_FILE}"

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
