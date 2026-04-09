# Local AI on Android: High-Performance LLMs via Termux
Welcome to the ultimate guide for running High-Performance Local AI (Large Language Models) directly on your Android phone using Termux.
This repository documents the exact commands, driver configurations, and fixes needed to run Llama 3.2 (1B), Qwen 2.5 (1.5B/7B), and cutting-edge BitNet models natively on modern Android hardware (specifically tested on the Snapdragon 7 Gen 3). **No root required.**
## 🚀 The 1-Click Installation (Recommended)
You don't need to manually configure compilers or compile from source. The easiest way to get started is to run our intelligent installer script. It automatically profiles your hardware, calculates memory pools, bypasses factory Adreno limits by installing Turnip (Mesa) drivers, and downloads the best models for your phone.
```bash
pkg update && pkg install wget -y
wget https://raw.githubusercontent.com/sanatani-hackers/LLama.cpp-termux/main/setup.sh
bash setup.sh

```
**How to run after installation:**
The script sets up a global bitnet command. Just run:
```bash
bitnet -hf Qwen/Qwen2.5-Coder-7B-Instruct-GGUF:*Q4_K_M.gguf -cnv

```
*(Or use bitnet -m /path/to/model.gguf -ngl 99 -p "Your prompt" for local files).*
## 🛠️ Manual Installation (Advanced Users)
If you prefer to build the engine from scratch, follow these manual steps.
### Step 1: System Prerequisites
Before building anything, prepare your Termux environment with the necessary compilers and custom open-source Vulkan drivers (Turnip/Mesa).
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
### Step 2: Download the Engine & Models
We use a specialized fork (qvac-fabric-llm.cpp) to run standard GGUFs and 1.58-bit (BitNet) models.
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
The CPU build utilizing NEON instructions is the fastest way to generate text on modern SoCs.
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
The official Adreno drivers crash on complex AI shader compilation. We bypass this by forcing the system to use open-source Turnip (Mesa) drivers.
```bash
mkdir build-gpu && cd build-gpu

# Configure with Vulkan and explicit library paths
LDFLAGS="-L$PREFIX/lib" CPPFLAGS="-I$PREFIX/include" \
cmake .. -G Ninja -DGGML_VULKAN=ON -DGGML_OPENMP=ON -DCMAKE_BUILD_TYPE=Release

export ASAN_OPTIONS=detect_leaks=0
cmake --build . --config Release -j $(nproc)

```
To run the GPU build safely, you MUST export the Turnip paths and use fewer threads (-t 3 max) to prevent memory bottlenecking:
```bash
export VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json 
export LD_LIBRARY_PATH=$HOME/qvac-fabric-llm.cpp/build-gpu/bin:$LD_LIBRARY_PATH

./build-gpu/bin/llama-cli -m ../models/qwen2.5-1.5b.gguf -ngl 99 -t 3 -p "Hi"

```
## 📊 Performance Benchmarks (Snapdragon 7 Gen 3)
These benchmarks were recorded on a Snapdragon 7 Gen 3 (Adreno 720) with 8GB of RAM running native Termux. Testing CPU (NEON) vs GPU (Turnip driver) memory bottlenecks across 3 different models.
| Model | Backend | Threads | Speed (Tokens/Sec) | Notes |
|---|---|---|---|---|
| Llama 3.2 (1B) (Q4_K_M) | CPU | -t 5 | ~14.0 t/s | 🏆 Extremely fast and stable |
| Llama 3.2 (1B) (Q4_K_M) | GPU (Turnip) | -t 3 | ~4.0 t/s | Offloads perfectly to GPU |
| Qwen 2.5 (1.5B) (Q4_K_M) | CPU | -t 5 | ~14.2 t/s | 🏆 Fastest overall performance |
| Qwen 2.5 (1.5B) (Q4_K_M) | GPU (Turnip) | -t 5 | ~3.60 t/s | CPU fights GPU for memory bus (44% lag) |
| Qwen 2.5 (1.5B) (Q4_K_M) | GPU (Turnip) | -t 3 | ~3.64 t/s | 🔋 GPU Sweet Spot. Low lag (18.4%), battery efficient |
| BitNet XL (1.58b) (TQ1_0) | CPU | -t 5 | Fast | Extreme low RAM usage (1-bit weights) |
| BitNet XL (1.58b) (TQ1_0) | GPU (Turnip) | -t 3 | Stable | Runs fully offloaded to Adreno 720 |

## ⚡ Snapdragon 870 (Adreno 650)
These benchmarks were recorded on a Snapdragon 870 (Adreno 650) with 6GB RAM running native Termux using Vulkan (Turnip driver). Testing full GPU offload behavior, performance, and stability.
| Model | Backend | Threads | Speed (Tokens/Sec) | Notes |
|---|---|---|---|---|
| Llama 3.2 (1B) (Q4_K_M) | GPU (Turnip) | -t 3 | ~3.82 t/s | 🚀 Full GPU offload (17/17 layers) |
| Qwen 2.5 (1.5B) (Q4_K_M) | GPU (Turnip) | -t 5 | ~2.79 t/s | ⚠️ Higher latency due to contention |


## 🚨 Troubleshooting: Errors vs. Successes
If things break, compare your terminal output to these examples to find the fix.
### ❌ Error 1: The "Tagged Pointer" Crash
**What you see:**
```text
Segmentation fault

```
Happens immediately when trying to compile cmake --build or run llama-cli.
**The Fix:** Android 11+ has strict memory tagging. Disable it for the session:
```bash
export ASAN_OPTIONS=detect_leaks=0

```
### ❌ Error 2: Missing Vulkan Compiler
**What you see during CMake:**
```text
Could NOT find Vulkan (missing: Vulkan_INCLUDE_DIR glslc)

```
**The Fix:** You are missing the shader compiler headers.
```bash
pkg install vulkan-headers shaderc

```
### ❌ Error 3: Adreno Driver Pipeline Crash
**What you see when running Vulkan LLM:**
```text
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
**What you see when running:** ./bin/llama-cli --list-devices
```text
Available devices:

```
**The Fix:** Termux doesn't know where your compiled GPU libraries are.
```bash
export LD_LIBRARY_PATH=$HOME/qvac-fabric-llm.cpp/build-gpu/bin:$LD_LIBRARY_PATH

```
### ✅ SUCCESS: What a perfect GPU run looks like
If your environment variables are correct, running --list-devices or initiating the chat will output this specific line:
```text
ggml_vulkan: Found 1 Vulkan devices:
ggml_vulkan: 0 = Turnip Adreno (TM) 720 (turnip Mesa driver) | uma: 1 | fp16: 1

```
## 📝 License & Credits
**License:** MIT
**Credits:** Built using llama.cpp and the amazing Turnip/Mesa open-source driver project.
