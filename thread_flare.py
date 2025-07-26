import os
import sys
import threading
import time
import psutil
import multiprocessing
import subprocess
import signal
from ctypes import CDLL, c_int

def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)

def print_proc_limits():
    log("=== Process Limits ===")
    try:
        with open("/proc/self/limits") as f:
            for line in f:
                if "processes" in line.lower():
                    log(f"Proc limits: {line.strip()}")
    except Exception as e:
        log(f"Failed to read /proc/self/limits: {e}")

    # Try different methods to get process limits
    try:
        import resource
        nproc_soft, nproc_hard = resource.getrlimit(resource.RLIMIT_NPROC)
        log(f"Process limit (resource): soft={nproc_soft}, hard={nproc_hard}")
    except Exception as e:
        log(f"Failed to get process limits via resource module: {e}")
    
    # Try ulimit with error handling
    try:
        ulimit_result = subprocess.run(['sh', '-c', 'ulimit -u'], 
                                     capture_output=True, text=True, timeout=5)
        if ulimit_result.returncode == 0:
            log(f"ulimit -u: {ulimit_result.stdout.strip()}")
        else:
            log(f"ulimit -u failed: {ulimit_result.stderr.strip()}")
    except Exception as e:
        log(f"ulimit command not available: {e}")

def test_thread_limit():
    log("=== Spawning threads until failure ===")
    threads = []
    try:
        while True:
            t = threading.Thread(target=time.sleep, args=(10,))
            t.start()
            threads.append(t)
            if len(threads) % 100 == 0:
                log(f"Created {len(threads)} threads...")
    except Exception as e:
        log(f"Thread creation failed at {len(threads)} threads: {e}")

def check_cgroup_v1_limits():
    """Test cgroup v1 detection and limits"""
    log("=== Checking cgroup v1 limits ===")
    try:
        # Check if cgroup v1 is mounted
        cgroup_mounts = []
        with open("/proc/mounts") as f:
            for line in f:
                if "cgroup" in line and "cgroup2" not in line:
                    cgroup_mounts.append(line.strip())
        
        if cgroup_mounts:
            log(f"Found {len(cgroup_mounts)} cgroup v1 mounts")
            for mount in cgroup_mounts[:3]:  # Show first 3
                log(f"  {mount}")
        else:
            log("No cgroup v1 mounts found")
            
            # Provide interpretation
            try:
                # Check if cgroup v2 is available
                cgroup2_available = os.path.exists("/sys/fs/cgroup/cgroup.controllers")
                if cgroup2_available:
                    log("→ This indicates the system is using cgroup v2 (unified hierarchy)")
                    
                    # Check kernel version for context
                    try:
                        with open("/proc/version") as f:
                            kernel_version = f.read().strip()
                            log(f"→ Kernel: {kernel_version.split()[2]}")
                            
                        # Modern kernels default to cgroup v2
                        import platform
                        if "Ubuntu" in platform.platform() or "Debian" in platform.platform():
                            log("→ Modern Ubuntu/Debian systems default to cgroup v2")
                        elif "microsoft" in platform.platform().lower():
                            log("→ WSL2 environment typically uses cgroup v2")
                    except:
                        pass
                else:
                    log("→ No cgroup v1 or v2 detected - unusual configuration")
            except Exception as e:
                log(f"→ Could not determine cgroup configuration: {e}")
            return

        # Check pids controller in v1
        pids_max_path = None
        with open("/proc/self/cgroup") as f:
            for line in f:
                if "pids:" in line:
                    pids_path = line.strip().split(":")[-1]
                    candidate = f"/sys/fs/cgroup/pids{pids_path}/pids.max"
                    if os.path.isfile(candidate):
                        pids_max_path = candidate
                        break

        if pids_max_path:
            with open(pids_max_path) as f:
                pids_max = f.read().strip()
            log(f"cgroup v1 pids.max: {pids_max} ({pids_max_path})")
        else:
            log("cgroup v1 pids.max not found")
            
        # Check memory controller in v1
        memory_limit_path = None
        with open("/proc/self/cgroup") as f:
            for line in f:
                if "memory:" in line:
                    memory_path = line.strip().split(":")[-1]
                    candidate = f"/sys/fs/cgroup/memory{memory_path}/memory.limit_in_bytes"
                    if os.path.isfile(candidate):
                        memory_limit_path = candidate
                        break

        if memory_limit_path:
            with open(memory_limit_path) as f:
                memory_limit = f.read().strip()
            # Convert to GB for readability
            try:
                memory_gb = int(memory_limit) / (1024**3)
                log(f"cgroup v1 memory limit: {memory_gb:.2f} GB ({memory_limit} bytes)")
            except:
                log(f"cgroup v1 memory limit: {memory_limit}")
        else:
            log("cgroup v1 memory limit not found")
            
    except Exception as e:
        log(f"Failed to check cgroup v1 info: {e}")

def check_cgroup_v2_limits():
    """Test cgroup v2 detection and limits"""
    log("=== Checking cgroup v2 limits ===")
    try:
        # Check if cgroup v2 is mounted
        cgroup2_mounted = False
        with open("/proc/mounts") as f:
            for line in f:
                if "cgroup2" in line:
                    cgroup2_mounted = True
                    log(f"cgroup v2 mount: {line.strip()}")
                    break
        
        if not cgroup2_mounted:
            log("cgroup v2 not mounted")
            return
            
        # Detect cgroup v2 filesystem type
        cgroup_version = os.popen("stat -fc %T /sys/fs/cgroup").read().strip()
        log(f"cgroup filesystem type: {cgroup_version}")
        
        # Get current cgroup path
        cgroup_path = None
        with open("/proc/self/cgroup") as f:
            for line in f:
                if line.startswith("0::"):
                    cgroup_path = line.strip().split("::")[-1]
                    break
        
        if not cgroup_path:
            log("Could not determine cgroup v2 path")
            return
            
        log(f"Current cgroup v2 path: {cgroup_path}")
        
        # Check pids.max in v2
        pids_max_file = f"/sys/fs/cgroup{cgroup_path}/pids.max"
        if os.path.isfile(pids_max_file):
            with open(pids_max_file) as f:
                pids_max = f.read().strip()
            log(f"cgroup v2 pids.max: {pids_max}")
        else:
            log("cgroup v2 pids.max not found")
            
        # Check memory.max in v2
        memory_max_file = f"/sys/fs/cgroup{cgroup_path}/memory.max"
        if os.path.isfile(memory_max_file):
            with open(memory_max_file) as f:
                memory_max = f.read().strip()
            try:
                if memory_max != "max":
                    memory_gb = int(memory_max) / (1024**3)
                    log(f"cgroup v2 memory.max: {memory_gb:.2f} GB ({memory_max} bytes)")
                else:
                    log(f"cgroup v2 memory.max: {memory_max} (unlimited)")
            except:
                log(f"cgroup v2 memory.max: {memory_max}")
        else:
            log("cgroup v2 memory.max not found")
            
        # Check cpu.max in v2
        cpu_max_file = f"/sys/fs/cgroup{cgroup_path}/cpu.max"
        if os.path.isfile(cpu_max_file):
            with open(cpu_max_file) as f:
                cpu_max = f.read().strip()
            log(f"cgroup v2 cpu.max: {cpu_max}")
        else:
            log("cgroup v2 cpu.max not found")
            
    except Exception as e:
        log(f"Failed to check cgroup v2 info: {e}")

def test_ray_comprehensive_resources():
    """Test comprehensive Ray resource detection APIs"""
    log("=== Testing Ray comprehensive resource detection ===")
    try:
        import ray
        ray.init(ignore_reinit_error=True, log_to_driver=False)
        log("Ray initialized for comprehensive resource testing")
        
        # Test cluster_resources()
        log("--- Ray cluster_resources() ---")
        cluster_resources = ray.cluster_resources()
        for k, v in cluster_resources.items():
            log(f"Cluster resource: {k} = {v}")
            
        # Test available_resources()
        log("--- Ray available_resources() ---")
        available_resources = ray.available_resources()
        for k, v in available_resources.items():
            log(f"Available resource: {k} = {v}")
            
        # Test nodes() API
        log("--- Ray nodes() ---")
        try:
            nodes = ray.nodes()
            log(f"Number of nodes: {len(nodes)}")
            for i, node in enumerate(nodes):
                log(f"Node {i}: alive={node.get('Alive', 'unknown')}, "
                    f"resources={node.get('Resources', {})}")
        except Exception as e:
            log(f"ray.nodes() failed: {e}")
            
        # Test state API if available
        log("--- Ray state API ---")
        try:
            # Try to import state API
            from ray.util.state import list_nodes
            state_nodes = list_nodes()
            log(f"State API nodes: {len(state_nodes)}")
            for node in state_nodes:
                log(f"State node: {node.node_id[:8]}... resources={node.resources}")
        except ImportError:
            log("Ray state API not available (older Ray version)")
        except Exception as e:
            log(f"Ray state API failed: {e}")
            
        # Test Ray's internal resource detection
        log("--- Ray internal resource detection ---")
        try:
            # Get Ray context for more detailed info
            context = ray.get_runtime_context()
            log(f"Ray runtime context: node_id={context.node_id.hex()[:8]}...")
        except Exception as e:
            log(f"Ray runtime context failed: {e}")
            
        # Test resource scheduling
        log("--- Ray resource scheduling test ---")
        try:
            @ray.remote(num_cpus=0.1)
            def resource_test_task():
                import os
                return {
                    'pid': os.getpid(),
                    'available_resources': ray.available_resources()
                }
            
            future = resource_test_task.remote()
            result = ray.get(future, timeout=5)
            log(f"Resource test task result: pid={result['pid']}, "
                f"resources={result['available_resources']}")
        except Exception as e:
            log(f"Ray resource scheduling test failed: {e}")
            
    except Exception as e:
        log(f"Ray comprehensive resource detection failed: {e}")
        
def test_ray_cgroup_detection():
    """Test how Ray detects and uses cgroup limits"""
    log("=== Testing Ray cgroup detection ===")
    try:
        import ray
        
        # Initialize Ray with specific memory settings
        log("--- Ray initialization with cgroup awareness ---")
        ray.init(ignore_reinit_error=True, 
                log_to_driver=False,
                object_store_memory=50_000_000)  # 50MB
        
        # Check what Ray detected for memory
        cluster_resources = ray.cluster_resources()
        memory_resources = {k: v for k, v in cluster_resources.items() 
                          if 'memory' in k.lower()}
        log(f"Ray detected memory resources: {memory_resources}")
        
        # Test Ray's object store memory detection
        log("--- Ray object store memory ---")
        object_store_memory = cluster_resources.get('object_store_memory', 'Not found')
        if object_store_memory != 'Not found':
            object_store_gb = object_store_memory / (1024**3)
            log(f"Object store memory: {object_store_gb:.2f} GB ({object_store_memory} bytes)")
        else:
            log("Object store memory not found in cluster resources")
            
        # Compare with system memory
        import psutil
        system_memory_gb = psutil.virtual_memory().total / (1024**3)
        ray_memory = cluster_resources.get('memory', 0) / (1024**3)
        log(f"Memory comparison: System={system_memory_gb:.2f}GB, Ray={ray_memory:.2f}GB")
        
        # Test CPU detection
        ray_cpu = cluster_resources.get('CPU', 0)
        system_cpu = psutil.cpu_count(logical=True)
        log(f"CPU comparison: System={system_cpu}, Ray={ray_cpu}")
        
        ray.shutdown()
        log("Ray cgroup detection test completed")
        
    except Exception as e:
        log(f"Ray cgroup detection failed: {e}")

def print_system_info():
    """Print comprehensive system information including GPU detection"""
    log("=== System Information ===")
    
    # CPU Information
    log(f"CPU cores (logical): {psutil.cpu_count(logical=True)}")
    log(f"CPU cores (physical): {psutil.cpu_count(logical=False)}")
    
    # Memory Information
    memory = psutil.virtual_memory()
    log(f"Memory total: {memory.total / (1024**3):.2f} GB")
    log(f"Memory available: {memory.available / (1024**3):.2f} GB")
    log(f"Memory used: {memory.percent:.1f}%")
    
    # System Type Detection
    log("=== Environment Detection ===")
    
    # Check if running in container
    container_type = detect_container_type()
    log(f"Container type: {container_type}")
    
    # Check if running in Kubernetes/OpenShift
    k8s_info = detect_kubernetes_environment()
    log(f"Kubernetes environment: {k8s_info}")
    
    # GPU Detection
    log("=== GPU Detection ===")
    gpu_info = detect_gpu_resources()
    for gpu_line in gpu_info:
        log(gpu_line)
    
    # Architecture and OS info
    log("=== Platform Information ===")
    import platform
    log(f"Architecture: {platform.machine()}")
    log(f"Platform: {platform.platform()}")
    log(f"Processor: {platform.processor() or 'Unknown'}")

def detect_container_type():
    """Detect what type of container environment we're running in"""
    try:
        # Check for Docker
        if os.path.exists("/.dockerenv"):
            return "Docker"
        
        # Check for Podman
        if os.path.exists("/run/.containerenv"):
            return "Podman"
        
        # Check cgroup for container indicators
        try:
            with open("/proc/1/cgroup") as f:
                cgroup_content = f.read()
                if "docker" in cgroup_content:
                    return "Docker (via cgroup)"
                elif "containerd" in cgroup_content:
                    return "containerd"
                elif "crio" in cgroup_content:
                    return "CRI-O"
        except:
            pass
        
        return "None detected"
    except Exception as e:
        return f"Detection failed: {e}"

def detect_kubernetes_environment():
    """Detect Kubernetes/OpenShift environment"""
    try:
        k8s_indicators = []
        
        # Check for Kubernetes service account
        if os.path.exists("/var/run/secrets/kubernetes.io/serviceaccount"):
            k8s_indicators.append("K8s ServiceAccount")
        
        # Check environment variables
        if os.getenv("KUBERNETES_SERVICE_HOST"):
            k8s_indicators.append("K8s Service Host")
        
        # Check for OpenShift specific indicators
        if os.getenv("OPENSHIFT_BUILD_NAME") or os.getenv("OPENSHIFT_DEPLOYMENT_NAME"):
            k8s_indicators.append("OpenShift")
        
        # Check hostname patterns
        hostname = os.uname().nodename
        if any(pattern in hostname for pattern in ["-", "pod", "deployment"]):
            k8s_indicators.append(f"K8s-like hostname: {hostname}")
        
        return ", ".join(k8s_indicators) if k8s_indicators else "None detected"
    except Exception as e:
        return f"Detection failed: {e}"

def detect_gpu_resources():
    """Detect GPU resources using multiple methods"""
    gpu_info = []
    
    # Method 1: nvidia-smi command
    try:
        result = subprocess.run(["nvidia-smi", "--query-gpu=name,memory.total,driver_version", 
                               "--format=csv,noheader,nounits"], 
                              capture_output=True, text=True, timeout=10)
        if result.returncode == 0 and result.stdout.strip():
            gpu_info.append("NVIDIA GPUs detected via nvidia-smi:")
            for i, line in enumerate(result.stdout.strip().split('\n')):
                if line.strip():
                    parts = [p.strip() for p in line.split(',')]
                    if len(parts) >= 3:
                        name, memory, driver = parts[0], parts[1], parts[2]
                        gpu_info.append(f"  GPU {i}: {name}, {memory}MB memory, driver {driver}")
        else:
            gpu_info.append("nvidia-smi: No NVIDIA GPUs found or command failed")
    except FileNotFoundError:
        gpu_info.append("nvidia-smi: Command not found")
        gpu_info.append("→ NVIDIA drivers/tools not installed in container")
        gpu_info.append("→ For GPU support, install nvidia-container-toolkit and use --gpus flag")
    except Exception as e:
        gpu_info.append(f"nvidia-smi: Error - {e}")
    
    # Method 2: Check /proc/driver/nvidia
    try:
        if os.path.exists("/proc/driver/nvidia"):
            gpu_info.append("NVIDIA driver detected in /proc/driver/nvidia")
            if os.path.exists("/proc/driver/nvidia/version"):
                with open("/proc/driver/nvidia/version") as f:
                    version_info = f.read().strip()
                    gpu_info.append(f"  Driver version info: {version_info.split()[0] if version_info else 'Unknown'}")
        else:
            gpu_info.append("No NVIDIA driver found in /proc/driver/nvidia")
    except Exception as e:
        gpu_info.append(f"/proc/driver/nvidia check failed: {e}")
    
    # Method 3: Check for GPU device files
    try:
        gpu_devices = []
        for i in range(16):  # Check for up to 16 GPUs
            if os.path.exists(f"/dev/nvidia{i}"):
                gpu_devices.append(f"nvidia{i}")
        
        if gpu_devices:
            gpu_info.append(f"GPU device files: {', '.join(gpu_devices)}")
        else:
            gpu_info.append("No GPU device files found in /dev/")
            
        # Check for nvidia-uvm and nvidia-modeset
        special_devices = []
        for device in ["nvidia-uvm", "nvidia-modeset", "nvidiactl"]:
            if os.path.exists(f"/dev/{device}"):
                special_devices.append(device)
        
        if special_devices:
            gpu_info.append(f"NVIDIA special devices: {', '.join(special_devices)}")
            
    except Exception as e:
        gpu_info.append(f"GPU device file check failed: {e}")
    
    # Method 4: Try to detect via Ray (if available)
    try:
        import ray
        if ray.is_initialized():
            cluster_resources = ray.cluster_resources()
            gpu_resources = {k: v for k, v in cluster_resources.items() if 'gpu' in k.lower()}
            if gpu_resources:
                gpu_info.append("Ray detected GPU resources:")
                for resource, count in gpu_resources.items():
                    gpu_info.append(f"  {resource}: {count}")
            else:
                gpu_info.append("Ray: No GPU resources detected in cluster")
    except ImportError:
        gpu_info.append("Ray not available for GPU detection")
    except Exception as e:
        gpu_info.append(f"Ray GPU detection failed: {e}")
    
    return gpu_info if gpu_info else ["No GPU detection methods succeeded"]

def test_multiprocessing_fork():
    """Test multiprocessing fork context like nv-ingest uses"""
    log("=== Testing multiprocessing fork context ===")
    try:
        ctx = multiprocessing.get_context("fork")
        log(f"Multiprocessing context: {ctx}")
        log(f"Available start methods: {multiprocessing.get_all_start_methods()}")
        
        # Test simple process creation
        def worker_func():
            return os.getpid()
        
        process = ctx.Process(target=worker_func, daemon=False)
        process.start()
        process.join(timeout=5)
        
        if process.is_alive():
            process.terminate()
            log("Process creation test: TIMEOUT")
        else:
            log(f"Process creation test: SUCCESS (exit code: {process.exitcode})")
            
    except Exception as e:
        log(f"Multiprocessing fork test failed: {e}")

def test_subprocess_spawning():
    """Test subprocess spawning patterns like nv-ingest pipeline"""
    log("=== Testing subprocess spawning ===")
    try:
        # Test basic subprocess creation
        result = subprocess.run(["python3", "-c", "import os; print(f'PID: {os.getpid()}'); exit(0)"], 
                              capture_output=True, text=True, timeout=10)
        log(f"Subprocess test result: {result.returncode}")
        log(f"Subprocess output: {result.stdout.strip()}")
        
        # Test process group creation (like nv-ingest does)
        cmd = ["python3", "-c", "import os; print(f'PGID: {os.getpgid(0)}'); exit(0)"]
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, 
                               preexec_fn=os.setsid, text=True)
        stdout, stderr = proc.communicate(timeout=10)
        log(f"Process group test: {proc.returncode}")
        log(f"Process group output: {stdout.strip()}")
        
    except Exception as e:
        log(f"Subprocess spawning test failed: {e}")

def test_signal_handling():
    """Test signal handling patterns used in nv-ingest"""
    log("=== Testing signal handling ===")
    try:
        # Test signal availability
        available_signals = []
        for sig_name in ['SIGKILL', 'SIGTERM', 'SIGINT']:
            if hasattr(signal, sig_name):
                available_signals.append(sig_name)
        log(f"Available signals: {available_signals}")
        
        # Test prctl availability (used for PDEATHSIG)
        try:
            libc = CDLL("libc.so.6")
            log("prctl (PDEATHSIG) support: AVAILABLE")
        except Exception:
            log("prctl (PDEATHSIG) support: NOT AVAILABLE")
            
    except Exception as e:
        log(f"Signal handling test failed: {e}")

def test_ray_pipeline_simulation():
    """Simulate Ray pipeline patterns from nv-ingest"""
    log("=== Testing Ray pipeline simulation ===")
    try:
        import ray
        
        # Initialize Ray with specific config like nv-ingest might
        ray.init(ignore_reinit_error=True, log_to_driver=False)
        log("Ray initialized for pipeline simulation")
        
        # Test Ray remote function (basic pattern)
        @ray.remote
        def pipeline_task(data):
            import time
            time.sleep(0.1)  # Simulate work
            return f"Processed: {data}"
        
        # Test task submission and retrieval
        futures = []
        for i in range(5):
            future = pipeline_task.remote(f"data_{i}")
            futures.append(future)
        
        results = ray.get(futures)
        log(f"Pipeline simulation completed: {len(results)} tasks")
        
        # Test Ray cluster resources after pipeline work
        resources = ray.cluster_resources()
        for k, v in resources.items():
            log(f"Ray resource after pipeline: {k} = {v}")
            
        ray.shutdown()
        log("Ray pipeline simulation completed successfully")
        
    except Exception as e:
        log(f"Ray pipeline simulation failed: {e}")

def test_file_descriptor_limits():
    """Test file descriptor limits that might affect Ray/multiprocessing"""
    log("=== Testing file descriptor limits ===")
    try:
        import resource
        
        # Get current limits
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        log(f"File descriptor limit - soft: {soft}, hard: {hard}")
        
        # Test opening multiple file descriptors
        fds = []
        try:
            for i in range(min(100, soft // 2)):
                fd = os.open('/dev/null', os.O_RDONLY)
                fds.append(fd)
            log(f"Successfully opened {len(fds)} file descriptors")
        finally:
            for fd in fds:
                os.close(fd)
                
    except Exception as e:
        log(f"File descriptor test failed: {e}")

if __name__ == "__main__":
    log("Starting Thread Flare (nv-ingest compatible)...")
    log(f"Python version: {sys.version}")
    
    # Basic system checks
    print_proc_limits()
    print_system_info()
    test_file_descriptor_limits()
    
    # Comprehensive cgroup testing
    check_cgroup_v1_limits()
    check_cgroup_v2_limits()
    
    # nv-ingest specific tests
    test_signal_handling()
    test_multiprocessing_fork()
    test_subprocess_spawning()
    
    # Comprehensive Ray tests
    test_ray_comprehensive_resources()
    test_ray_cgroup_detection()
    test_ray_pipeline_simulation()
    
    # Thread limit test (potentially disruptive, so run last)
    test_thread_limit()
