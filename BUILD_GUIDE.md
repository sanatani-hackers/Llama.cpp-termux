# Building `llama.cpp` on Android via Termux (Complete Guide)

Upstream Repository: [https://github.com/ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)

This document details the step-by-step process, environment configuration, troubleshooting resolutions, and commands used to build and verify **`llama-cli`** with **Mesa Turnip (Adreno Vulkan)** and **ARM NEON/i8mm** CPU acceleration on Android without root.

---

## 1. System & Hardware Profile

The build was configured and compiled directly on the target device:

- **Device SoC**: Qualcomm Snapdragon 7 Gen 3 (`SM7550`)
- **GPU**: Adreno 720
- **CPU**: 8-core ARMv8.2+ (Cortex-A715 performance cores + Cortex-A510 efficiency cores)
  - Hardware Vector Features: `asimd`, `fphp`, `asimdhp`, `asimdrdm`, `asimddp`, `i8mm`, `bf16`
- **Operating Environment**: Termux on Android 13+ (Linux 5.15 aarch64 kernel)
- **Memory**: 7.1 GiB RAM (~2.2 GiB available) + 7.5 GiB Swap

---

## 2. Prerequisites & Dependency Installation

To compile `llama.cpp` with Vulkan compute shader generation on Termux, specific system packages, compilers, and driver layers must be installed.

### Step 2.1: Base Build Tools
```bash
pkg update && pkg upgrade -y
pkg install -y git cmake clang ninja ndk-sysroot
```

### Step 2.2: Repositories & Open-Source Vulkan Stack
Stock Android Adreno proprietary Vulkan drivers crash or segfault on complex FP16 compute shaders (`adreno_mul_mat_vec_*`). Open-source **Mesa Turnip** (`freedreno`) bypasses this issue.

```bash
# Enable hardware and graphical package repositories
pkg install -y x11-repo tur-repo

# Install Vulkan loader, shader compiler, headers, and Turnip driver
pkg install -y vulkan-loader-generic \
               vulkan-headers \
               shaderc \
               spirv-tools \
               spirv-headers \
               mesa-vulkan-icd-freedreno
```

> [!NOTE]
> `spirv-headers` is mandatory for newer `llama.cpp` Vulkan CMake configurations. Without it, CMake will fail during `find_package(SPIRV-Headers)`.

---

## 3. Source Tree Setup

The official source code is hosted at:
- **Upstream Repository**: [https://github.com/ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)

Clone or extract into:
[`/data/data/com.termux/files/home/llama.cpp-master`](file:///data/data/com.termux/files/home/llama.cpp-master)

```bash
cd ~
# Either clone directly:
git clone --depth=1 https://github.com/ggml-org/llama.cpp.git llama.cpp-master

# Or download and extract the master archive:
# wget https://github.com/ggml-org/llama.cpp/archive/refs/heads/master.tar.gz
# tar -xvf master.tar.gz
```

Directory structure highlights:
- `ggml/`: Core tensor computation library, CPU kernels, and Vulkan compute shaders (`.comp`)
- `tools/cli/`: Source code for `llama-cli`
- `common/`: Common helper and inference pipeline libraries

---

## 4. CMake Configuration

An out-of-source build was generated in `~/llama.cpp-master/build-gpu`.

### Configuration Command:
```bash
cd ~/llama.cpp-master
mkdir -p build-gpu && cd build-gpu

LDFLAGS="-L$PREFIX/lib" CPPFLAGS="-I$PREFIX/include" \
cmake .. -G Ninja \
  -DGGML_VULKAN=ON \
  -DCMAKE_BUILD_TYPE=Release
```

### Detected Toolchain & Hardware Features:
- **Compiler**: Clang 21.1.8
- **OpenMP**: Enabled (`-fopenmp=libomp`, version 5.1)
- **ARM Optimization Flags**: `-mcpu=native+dotprod+i8mm+nosve+nosme`
  - `HAVE_DOTPROD`: Yes
  - `HAVE_MATMUL_INT8`: Yes
  - `HAVE_FMA`: Yes
  - `HAVE_FP16_VECTOR_ARITHMETIC`: Yes
- **Vulkan Shader Capabilities**:
  - `GL_KHR_cooperative_matrix`: Supported
  - `GL_NV_cooperative_matrix2`: Supported
  - `GL_EXT_integer_dot_product`: Supported
  - `GL_EXT_bfloat16`: Supported

---

## 5. Compilation Process

Instead of compiling the entire repository (742+ targets, including all tests, benchmarks, and multi-modal examples), compilation was targeted strictly to **`llama-cli`** (375 targets). This prevented compiler out-of-memory (OOM) kills on Termux and reduced build time significantly.

### Compilation Command:
```bash
cd ~/llama.cpp-master/build-gpu
export ASAN_OPTIONS=detect_leaks=0
cmake --build . --config Release --target llama-cli -j 4
```

### Key Technical Considerations:
1. **Tagged Pointer Crash Workaround (`ASAN_OPTIONS=detect_leaks=0`)**:
   Android 11+ enforces strict memory tagging on heap pointers. Setting this environment variable prevents runtime `SIGSEGV` during shader generation and linking.
2. **Parallel Thread Limit (`-j 4`)**:
   Restricting ninja to 4 parallel jobs keeps RAM usage below 2 GiB, avoiding Android's `lowmemorykiller` while utilizing the performance cores.

### Artifacts Produced:
Located in [`~/llama.cpp-master/build-gpu/bin`](file:///data/data/com.termux/files/home/llama.cpp-master/build-gpu/bin):
- `llama-cli`: Primary text generation CLI executable
- `libllama.so`: Inference runtime engine
- `libggml-vulkan.so`: Vulkan compute backend
- `libggml-cpu.so`: CPU NEON/i8mm optimized backend
- `libggml-base.so`: Core tensor structure library

---

## 6. Verification & Hardware Confirmation

We verified the build and GPU driver linkage by querying available compute backends:

```bash
export VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json
export LD_LIBRARY_PATH=$HOME/llama.cpp-master/build-gpu/bin:$LD_LIBRARY_PATH
export ASAN_OPTIONS=detect_leaks=0

~/llama.cpp-master/build-gpu/bin/llama-cli --list-devices
```

### Output:
```text
Available devices:
  Vulkan0: Turnip Adreno (TM) 720 (5429 MiB, 2191 MiB free)
```

The Mesa Turnip driver cleanly initializes the Adreno 720 GPU with 2.2 GiB free unified memory.

---

## 7. Recommended Inference Commands

### ⚡ Option A: GPU Accelerated (Qualcomm Adreno + Turnip Vulkan)
Ideal for battery efficiency and offloading work from CPU cores. Use `-t 3` to prevent memory bus contention between CPU and GPU.

```bash
export VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json
export LD_LIBRARY_PATH=$HOME/llama.cpp-master/build-gpu/bin:$LD_LIBRARY_PATH
export ASAN_OPTIONS=detect_leaks=0

$HOME/llama.cpp-master/build-gpu/bin/llama-cli \
  -m /path/to/model.gguf \
  -ngl 99 \
  -t 3 \
  -c 2048 \
  -p "Explain quantum computing in simple terms."
```

### 🚀 Option B: Pure CPU (Qualcomm or MediaTek Dimensity/Helio)
Fastest token-generation speed using ARM NEON vectorization.

```bash
export LD_LIBRARY_PATH=$HOME/llama.cpp-master/build-gpu/bin:$LD_LIBRARY_PATH
export ASAN_OPTIONS=detect_leaks=0

$HOME/llama.cpp-master/build-gpu/bin/llama-cli \
  -m /path/to/model.gguf \
  -ngl 0 \
  -t 5 \
  -c 2048 \
  -p "Explain quantum computing in simple terms."
```

---

## 8. Guide for MediaTek Processors (Dimensity / Helio)

MediaTek chips use **ARM Mali / Immortalis** GPUs, which cannot use the Turnip driver. The stock Mali Vulkan driver frequently encounters shader crashes, and memory bandwidth contention makes Mali GPU inference slower than CPU.

For MediaTek devices, a **CPU-Only build** is strongly recommended:

### Build Command:
```bash
cd ~/llama.cpp-master
mkdir -p build-cpu && cd build-cpu

cmake .. -G Ninja -DGGML_OPENMP=ON -DCMAKE_BUILD_TYPE=Release
export ASAN_OPTIONS=detect_leaks=0
cmake --build . --config Release --target llama-cli -j 4
```

### Optimal Thread Recommendations:
- **Dimensity 9000/9200/9300/8300**: `-t 4` (targets the Cortex-X / Cortex-A715 performance cores).
- **Dimensity 7000/6000 series**: `-t 2` or `-t 4` (targets big Cortex-A78 cores).
- **Helio G99 / G85 / P35**: `-t 4` to `-t 6`.

---

## 9. Troubleshooting Reference

| Issue Encountered | Root Cause | Fix Applied |
| :--- | :--- | :--- |
| `find_package(SPIRV-Headers)` failure during CMake | Missing SPIRV header metadata in Termux | `pkg install spirv-headers` |
| `Compute pipeline creation failed` / Segfault | Stock Qualcomm Adreno driver shader compiler bug | Installed and set `VK_ICD_FILENAMES` to `freedreno_icd.aarch64.json` (Turnip Mesa) |
| Immediate `Segmentation fault` on startup | Android 11+ tagged pointer verification | `export ASAN_OPTIONS=detect_leaks=0` |
| Compiler Killed / Out of Memory (OOM) | Building all 742 targets concurrently with `-j 8` | Restricted build to target `--target llama-cli -j 4` |
