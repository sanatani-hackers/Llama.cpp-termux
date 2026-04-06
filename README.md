Here is a comprehensive and professionally structured README.md that captures all the hard work, troubleshooting, and commands you compiled. It separates the Stable Diffusion guide from the LLM guide, and clearly explains the CPU vs. GPU configurations.
You can copy and paste this directly into your GitHub repository!
Local AI on Android: Stable Diffusion & LLMs via Termux
Welcome to the ultimate guide for running High-Performance Local AI (Image Generation and Large Language Models) directly on your Android phone using Termux.
This repository documents the exact commands, fixes, and driver configurations needed to run Stable Diffusion 1.5, Llama 3.2 (1B), Qwen 2.5 (1.5B), and BitNet models on modern Android hardware (specifically tested on Snapdragon 7 Gen 3 / Adreno 720).
🛠️ System Prerequisites
Before building anything, you need to prepare your Termux environment with the necessary compilers, graphics headers, and custom open-source Vulkan drivers (Turnip/Mesa).

Bash


# Update system and install base build tools
pkg update && pkg upgrade -y
pkg install git cmake clang ninja

# Enable necessary repositories for graphical and hardware drivers
pkg install x11-repo tur-repo

# Install Vulkan headers, Shader compiler, and Turnip (Mesa) drivers
pkg install vulkan-loader-generic vulkan-headers shaderc ndk-sysroot
pkg install mesa-vulkan-icd-freedreno-dri3


🎨 Part 1: Stable Diffusion (Image Generation)
Note: On newer Snapdragon chips (like the 7 Gen 3), the GPU/Vulkan build of Stable Diffusion can cause heavy VRAM spikes leading to Termux crashes. We highly recommend using the highly stable CPU build provided below.
1. Build the CPU Engine

Bash


# Clone the repository
git clone --recursive https://github.com/leejet/stable-diffusion.cpp
cd stable-diffusion.cpp
mkdir build && cd build

# Configure and compile for CPU
cmake .. -G Ninja -DSD_WEBP=OFF
cmake --build . --config Release
cd ..


2. Download Model and Generate
We use a quantized Q4_0 model to fit perfectly into mobile RAM while maintaining great quality.

Bash


# Download the GGUF model
mkdir models
wget https://huggingface.co/second-state/stable-diffusion-v1-5-GGUF/resolve/main/stable-diffusion-v1-5-pruned-emaonly-Q4_0.gguf -O models/sd-v1.5-q4.gguf

# Generate an Image (CPU Mode)
./bin/sd-cli -m models/sd-v1.5-q4.gguf -p "a beautiful cyberpunk city at night, neon lights, flying cars, highly detailed, 4k masterpiece" -n "blurry, ugly, noisy, pixelated, abstract, low resolution" -H 512 -W 512 -t 4 --mmap --sampling-method euler_a --steps 15 -o my_cyberpunk_city.png -v


🤖 Part 2: Large Language Models (Llama 3.2 & Qwen 2.5)
This section uses a specialized fork to run standard GGUFs as well as cutting-edge 1.58-bit (BitNet) models.
1. Clone and Prepare

Bash


cd ~
git clone https://github.com/tetherto/qvac-fabric-llm.cpp
cd qvac-fabric-llm.cpp
mkdir models


2. Download the Models

Bash


# Qwen 2.5 (1.5B)
wget https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf -O models/qwen2.5-1.5b.gguf

# Llama 3.2 (1B)
wget https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf -O models/llama-3.2-1b.gguf

# BitNet (1.58-bit)
wget https://huggingface.co/qvac/fabric-llm-finetune-bitnet/resolve/main/1bitLLM-bitnet_b1_58-xl-tq1_0.gguf -O models/bitnet-xl.gguf


🔥 Build Option A: High-Speed CPU (Recommended for Speed)
On a Snapdragon 7 Gen 3, the CPU build utilizing NEON instructions is actually the fastest way to generate text, hitting roughly ~14 tokens/sec.

Bash


mkdir build-cpu && cd build-cpu
cmake .. -G Ninja -DGGML_OPENMP=ON -DCMAKE_BUILD_TYPE=Release

# Fix Android Tagged Pointers crash and build
export ASAN_OPTIONS=detect_leaks=0
cmake --build . --config Release -j $(nproc)
cd ..

# Run it! (Optimal setting is -t 5)
./build-cpu/bin/llama-cli -m models/qwen2.5-1.5b.gguf -c 2048 -t 5 --temp 0.7 -p "Explain the concept of cyberpunk to a time traveler from the year 1800."


⚡ Build Option B: GPU/Vulkan (Using Mesa Turnip Drivers)
Why do this? The official Android Adreno drivers crash on complex AI shader compilation (adreno_mul_mat_vec_q4_k_q8_1_f32). We bypass this by compiling for Vulkan and forcing the system to use open-source Turnip (Mesa) drivers.

Bash


mkdir build-gpu && cd build-gpu

# Configure with Vulkan and explicit library paths
LDFLAGS="-L$PREFIX/lib" CPPFLAGS="-I$PREFIX/include" \
cmake .. -G Ninja -DGGML_VULKAN=ON -DGGML_OPENMP=ON -DCMAKE_BUILD_TYPE=Release

# Fix Tagged Pointers and Build
export ASAN_OPTIONS=detect_leaks=0
cmake --build . --config Release -j $(nproc)
cd ..


Running the GPU Build:
To make the GPU build work, you must export the paths to the Turnip driver and your built libraries before running. Also, lower your thread count (-t 1 to -t 3) to prevent the CPU from bottlenecking the GPU's memory access!

Bash


# 1. Point to the Turnip Driver
export VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json 

# 2. Point to your custom Vulkan libraries
export LD_LIBRARY_PATH=$HOME/qvac-fabric-llm.cpp/build-gpu/bin:$LD_LIBRARY_PATH

# 3. Verify the Turnip Driver is detected
./build-gpu/bin/llama-cli --list-devices

# 4. Run the model fully offloaded (-ngl 99)
./build-gpu/bin/llama-cli -m models/qwen2.5-1.5b.gguf -ngl 99 -t 3 -p "Hi"


🪲 Common Errors & Fixes
Segmentation Fault during linking or running:
Cause: Android's strict memory tagging security.
Fix: Run export ASAN_OPTIONS=detect_leaks=0 before building or executing.
Could NOT find Vulkan (missing: Vulkan_INCLUDE_DIR glslc):
Cause: Missing shader compiler.
Fix: Ensure you ran pkg install vulkan-headers shaderc ndk-sysroot.
Available devices: (List is empty on GPU build):
Cause: Binary cannot find the Turnip driver.
Fix: You forgot to export the VK_ICD_FILENAMES and LD_LIBRARY_PATH variables.
Phone freezes/reboots during Stable Diffusion:
Cause: Adreno driver VRAM spike.
Fix: Stick to the CPU build for image generation.
If this guide helped you bring local AI to your Android device, please star the repository!
*** This structure covers literally every hurdle you jumped over and every command you verified. You did incredible work figuring all of this out! Let me know if you want to tweak any of the wording before you publish.
