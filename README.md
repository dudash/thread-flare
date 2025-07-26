# Thread Flare - Ray Debug Container

A Python-based debug container for testing Ray cluster resources, thread spawning, and cgroup limits on K8s variants.  
Vibe-coded :infinity: by Claude Sonnet 4 + Windsurf

## Container Variants

Thread Flare comes in two variants to suit different deployment needs:

### **Slim Variant** (Recommended)
- **Base**: Python 3.10-slim
- **Size**: ~400MB
- **Use Case**: CPU-only environments, general debugging
- **Ray**: 2.37.0 with default components
- **Build**: `./build-and-deploy.sh slim`
- **Run**: `./run-and-capture-logs.sh slim`

### **CUDA Variant** (GPU-Enabled)
- **Base**: NVIDIA CUDA 12.4.1 + Ubuntu 22.04
- **Size**: ~2GB
- **Use Case**: GPU-enabled environments, NVIDIA nv-ingest debugging
- **Ray**: 2.37.0 with full GPU support
- **Build**: `./build-and-deploy.sh cuda`
- **Run**: `./run-and-capture-logs.sh cuda`

## Features
- **Comprehensive Ray Testing**: Tests Ray 2.37.0+ with cluster_resources, available_resources, nodes() APIs
- **Ray Cgroup Detection**: Tests how Ray detects and uses cgroup memory/CPU limits
- **Ray Pipeline Simulation**: Simulates nv-ingest Ray pipeline patterns with remote tasks
- **Cgroup v1 & v2 Detection**: Comprehensive testing of both cgroup versions
- **Cgroup Limits Analysis**: Tests pids.max, memory limits, and CPU limits in both versions
- **Multiprocessing Fork Testing**: Tests fork context used by nv-ingest
- **Subprocess Spawning**: Tests process group creation patterns
- **Signal Handling**: Tests PDEATHSIG and signal availability
- **Thread Limit Testing**: Spawns threads until failure to test system limits
- **File Descriptor Limits**: Tests FD limits that affect Ray/multiprocessing
- **System Introspection**: Uses psutil for CPU and memory information
- **Real-time Logging**: Outputs timestamped logs to stdout
- **OpenShift**: Support to run as a pod in OpenShift

## Quick Start

### Local Development

```bash
# Build the container
./build-and-deploy.sh

# Run locally
docker run --rm -it thread-flare:latest
```
   ```bash
   ./build-and-deploy.sh slim
   # OR: docker build -f Dockerfile.slim -t thread-flare-slim:latest .
   ```

2. **Run locally**:
   ```bash
   ./run-and-capture-logs.sh slim
   # OR: docker run --rm thread-flare-slim:latest
   ```

3. **Deploy to K8s**:
   ```bash
   kubectl apply -f pod.yaml  # Uses slim variant by default
   kubectl logs -f pod/thread-flare
   ```

### CUDA Variant (GPU-enabled)

1. **Build the container**:
   ```bash
   ./build-and-deploy.sh cuda
   # OR: docker build -f Dockerfile.cuda -t thread-flare-cuda:latest .
   ```

2. **Run locally** (requires nvidia-container-toolkit):
   ```bash
   ./run-and-capture-logs.sh cuda
   # OR: docker run --gpus all --rm thread-flare-cuda:latest
   ```

3. **Deploy to K8s** (requires GPU nodes):
   ```bash
   # Edit pod.yaml to use thread-flare-cuda:latest
   kubectl apply -f pod.yaml
   kubectl logs -f pod/thread-flare
   ```

4. **View logs**:
   ```bash
   oc logs -f pod/thread-flare
   ```

## Log Capture and Analysis

Thread Flare includes scripts to automatically capture and analyze detailed test results:

### Local Testing with Log Capture

```bash
# Run Thread Flare locally and save logs to timestamped files
./run-and-capture-logs.sh
```

This creates:
- `logs/thread_flare_YYYYMMDD_HHMMSS.log` - Complete detailed output
- `logs/thread_flare_YYYYMMDD_HHMMSS_summary.txt` - Key metrics summary

### Kubernetes Testing with Log Capture

```bash
# Deploy to K8s and capture logs
./run-k8s-and-capture-logs.sh

# With custom namespace and timeout
NAMESPACE=my-namespace TIMEOUT=600 ./run-k8s-and-capture-logs.sh
```

This automatically:
1. Deploys the Thread Flare pod
2. Waits for pod to be ready
3. Captures all output to timestamped log files
4. Generates a summary with key metrics
5. Cleans up the pod when done

### Log Analysis

The summary files extract key information:
- **Python version** and system resources
- **Cgroup detection** results (v1/v2)
- **Ray resource detection** and comparison with system
- **Thread limit** testing results
- **Test status** and any failures

Example summary output:
```
Python Version: 3.12.11
System Resources: 16 CPU cores, 15.03 GB RAM, 10.72 GB available, 28.7% used
Environment: Docker container, x86_64 architecture
GPU Detection: nvidia-smi found 2 GPUs (RTX 4090, 24GB each) or "Command not found"
Cgroup v2: pids.max: 18456, memory.max: unlimited
Ray Resources: 16 CPU, 9.97GB memory, 4.27GB object store
Thread Test: Created 18,391 threads before failure
Warnings: /dev/shm size warning, Ray deprecation warning
Test Status: ✅ All tests completed successfully
```

## Files

- `Dockerfile` - Container definition with Python 3.12, Ray 2.37.0+, and psutil
- `thread_flare.py` - Main Thread Flare script that runs all tests
- `openshift-pod.yaml` - OpenShift pod specification
- `build-and-deploy.sh` - Build and deployment helper script
- `run-and-capture-logs.sh` - **NEW**: Run locally and capture detailed logs to files
- `run-k8s-and-capture-logs.sh` - **NEW**: Deploy to K8s and capture logs

## What It Tests

1. **Process Limits**: Reads `/proc/self/limits` and `ulimit -u`
2. **System Resources**: CPU cores, memory usage, and availability via psutil
3. **Environment Detection**: Container type (Docker/Podman), Kubernetes environment
4. **GPU Detection**: NVIDIA GPU detection via multiple methods:
   - `nvidia-smi` command output with GPU names, memory, and driver versions
   - `/proc/driver/nvidia` driver detection
   - GPU device files in `/dev/` (nvidia0, nvidia1, etc.)
   - Ray GPU resource detection
5. **Platform Information**: Architecture, OS platform, processor type
6. **Cgroup Detection**: Both v1 and v2 cgroup mounts, pids.max, memory limits
7. **Ray Resource Detection**: Multiple Ray APIs for comprehensive cluster resource detection
8. **Thread Spawning**: Creates threads until system failure to test limits
9. **Multiprocessing**: Fork context testing like nv-ingest uses
10. **Subprocess Spawning**: Process group management and signal handling
11. **File Descriptor Limits**: Tests FD limits that affect Ray/multiprocessing
12. **Ray Pipeline Simulation**: Simulates nv-ingest Ray remote task patterns

## Expected Output

The container will output timestamped logs showing:
- Python version (should be 3.12.x)
- System process limits and file descriptor limits
- CPU and memory information via psutil
- Comprehensive cgroup v1 detection (mounts, pids.max, memory limits)
- Comprehensive cgroup v2 detection (mounts, pids.max, memory.max, cpu.max)
- Signal handling capabilities (including PDEATHSIG)
- Multiprocessing fork context testing
- Subprocess spawning and process group creation
- Ray comprehensive resource detection (cluster_resources, available_resources, nodes)
- Ray vs system resource comparison (memory/CPU detection differences)
- Ray pipeline simulation with remote tasks
- Thread creation progress until failure

## Troubleshooting

- Ensure your container registry is accessible from your k8s
- Check resource limits in the pod specification
- Verify Ray version compatibility with your environment
