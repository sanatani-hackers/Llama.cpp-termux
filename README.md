# Local AI on Android: Stable Diffusion & LLMs via Termux

The ultimate guide for running High-Performance Local AI (Image Generation and Large Language Models) directly on your Android phone using Termux.

This repository documents the exact commands, driver configurations, and fixes needed to run Stable Diffusion 1.5, Llama 3.2 (1B), Qwen 2.5 (1.5B), and BitNet models natively on modern Android hardware (specifically tested on Snapdragon 7 Gen 3). **No root required.**

## 🛠️ Step 1: System Prerequisites

Prepare your Termux environment with necessary compilers and custom open-source Vulkan drivers (Turnip/Mesa):

```bash
# Update system and install base build tools
pkg update && pkg upgrade -y
pkg install git cmake clang ninja

# Enable necessary repositories for graphical and hardware drivers
pkg install x11-repo tur-repo

# Install Vulkan headers, Shader compiler, and Turnip (Mesa) drivers
pkg install vulkan-loader-generic vulkan-headers shaderc ndk-sysroot
pkg install mesa-vulkan-icd-freedreno-dri3
```

## 🎨 Step 2: Stable Diffusion (Image Generation)

> **⚠️ DANGER ZONE: GPU vs. CPU for Stable Diffusion**
> 
> On newer Snapdragon chips (like the 7 Gen 3), the GPU/Vulkan build of Stable Diffusion can cause massive VRAM spikes, leading to the Android Low Memory Killer (LMK) crashing Termux or freezing your phone. **We highly recommend using the CPU build.**

### Build the CPU Engine

```bash
git clone --recursive https://github.com/leejet/stable-diffusion.cpp
cd stable-diffusion.cpp
mkdir build && cd build

# Configure and compile for CPU
cmake .. -G Ninja -DSD_WEBP=OFF
cmake --build . --config Release

# Optional: Strip binary to save space
strip bin/sd-cli
cd ..
```

### Download Model & Generate Image

```bash
mkdir models
wget https://huggingface.co/second-state/stable-diffusion-v1-5-GGUF/resolve/main/stable-diffusion-v1-5-pruned-emaonly-Q4_0.gguf -O models/sd-v1.5-q4.gguf

# Generate an Image (CPU Mode)
./build/bin/sd-cli -m models/sd-v1.5-q4.gguf -p "a beautiful cyberpunk city at night, neon lights, flying cars, highly detailed, 4k masterpiece" -n "blurry, ugly, noisy, pixelated, abstract, low resolution" -H 512 -W 512 -t 4 --mmap --sampling-method euler_a --steps 15 -o my_cyberpunk_city.png -v
```

## 🤖 Step 3: Large Language Models (LLMs)

Use a specialized fork (`qvac-fabric-llm.cpp`) to run standard GGUFs and cutting-edge 1.58-bit (BitNet) models:

```bash
cd ~
git clone https://github.com/tetherto/qvac-fabric-llm.cpp
cd qvac-fabric-llm.cpp
mkdir models

# Download Models
wget https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf -O models/qwen2.5-1.5b.gguf
wget https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf -O models/llama-3.2-1b.gguf
wget https://huggingface.co/qvac/fabric-llm-finetune-bitnet/resolve/main/1bitLLM-bitnet_b1_58-xl-tq1_0.gguf -O models/bitnet-xl.gguf
```

### Option A: CPU Build (Recommended for Pure Speed)

The CPU build utilizing NEON instructions is the fastest way to generate text on modern SoCs (~14 tokens/sec):

```bash
mkdir build-cpu && cd build-cpu
cmake .. -G Ninja -DGGML_OPENMP=ON -DCMAKE_BUILD_TYPE=Release

# Fix Tagged Pointers crash and build
export ASAN_OPTIONS=detect_leaks=0
cmake --build . --config Release -j $(nproc)

# Run it! (Optimal setting is -t 5)
./bin/llama-cli -m ../models/qwen2.5-1.5b.gguf -c 2048 -t 5 --temp 0.7 -p "Explain the concept of cyberpunk to a time traveler from the year 1800."
```

### Option B: GPU/Vulkan Build (Using Mesa Turnip Drivers)

The official Adreno drivers crash on complex AI shader compilation. Bypass this by forcing the system to use open-source Turnip (Mesa) drivers:

```bash
mkdir build-gpu && cd build-gpu

# Configure with Vulkan and explicit library paths
LDFLAGS="-L$PREFIX/lib" CPPFLAGS="-I$PREFIX/include" \
cmake .. -G Ninja -DGGML_VULKAN=ON -DGGML_OPENMP=ON -DCMAKE_BUILD_TYPE=Release

export ASAN_OPTIONS=detect_leaks=0
cmake --build . --config Release -j $(nproc)
```

**To run the GPU build safely**, you MUST export the Turnip paths and use fewer threads (-t 3 max) to prevent memory bottlenecking:

```bash
export VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json 
export LD_LIBRARY_PATH=$HOME/qvac-fabric-llm.cpp/build-gpu/bin:$LD_LIBRARY_PATH

./build-gpu/bin/llama-cli -m ../models/qwen2.5-1.5b.gguf -ngl 99 -t 3 -p "Hi"
```

## 🚨 Troubleshooting: Errors vs. Successes

Compare your terminal output to these examples to find the fix.

### ❌ Error 1: The "Tagged Pointer" Crash

**What you see:**
```
Segmentation fault
```

Happens immediately when trying to compile `cmake --build` or run `llama-cli`.

**The Fix:** Android 11+ has strict memory tagging. Disable it for the session:
```bash
export ASAN_OPTIONS=detect_leaks=0
```

### ❌ Error 2: Missing Vulkan Compiler

**What you see during CMake:**
```
Could NOT find Vulkan (missing: Vulkan_INCLUDE_DIR glslc)
```

**The Fix:** You are missing the shader compiler headers:
```bash
pkg install vulkan-headers shaderc
```

### ❌ Error 3: Adreno Driver Pipeline Crash

**What you see when running Vulkan LLM:**
```
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = Adreno (TM) 720 (Qualcomm Technologies Inc. Adreno Vulkan Driver)
...
ggml_vulkan: Compute pipeline creation failed for adreno_mul_mat_vec_q4_k_q8_1_f32
Segmentation fault
```

**The Fix:** The official Qualcomm driver cannot handle Q4_K math. You MUST switch to the Turnip driver:
```bash
export VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json
```

### ❌ Error 4: Empty Devices List

**What you see when running:**
```bash
./bin/llama-cli --list-devices
```
```
Available devices:
```

**The Fix:** Termux doesn't know where your compiled GPU libraries are:
```bash
export LD_LIBRARY_PATH=$HOME/qvac-fabric-llm.cpp/build-gpu/bin:$LD_LIBRARY_PATH
```

### ✅ SUCCESS: What a perfect GPU run looks like

If your environment variables are correct, running `--list-devices` or initiating the chat will output this specific line:
```
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = Turnip Adreno (TM) 720 (turnip Mesa driver) | uma: 1 | fp16: 1
```

## 📊 Threading Benchmarks (Snapdragon 7 Gen 3)

**Why not use 5+ threads on the GPU?** Because the CPU and GPU share the same memory (UMA). If the CPU uses too many threads, it blocks the GPU from accessing RAM, increasing "unaccounted time" (lag).

| Mode | Threads | Tokens/Sec | Unaccounted Time (Lag) | Note |
|------|---------|------------|------------------------|------|
| CPU (NEON) | `-t 5` | ~14.2 t/s | Low | Fastest option. Best for daily use. |
| GPU (Turnip) | `-t 5` | ~3.60 t/s | 44.3% (High) | High CPU interference. |
| GPU (Turnip) | `-t 3` | ~3.64 t/s | 18.4% (Low) | GPU Sweet Spot. Best battery efficiency. |

## 📝 License & Credits

**License:** MIT

**Credits:** Built using [llama.cpp](https://github.com/ggerganov/llama.cpp), [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp), and the amazing Turnip/Mesa open-source driver project.
```
