# Local AI on Android
## Stable Diffusion & LLMs via Termux

Run **image generation** and **large language models** directly on your Android device using **Termux**, with support for both **CPU** and **GPU/Vulkan** workflows.

This repository documents the exact setup, commands, fixes, and driver configuration used to run:

- **Stable Diffusion 1.5**
- **Llama 3.2 (1B)**
- **Qwen 2.5 (1.5B)**
- **BitNet models**

Tested on modern Android hardware, including **Snapdragon 7 Gen 3 / Adreno 720**.

---

## Overview

This guide is split into two parts:

1. **Stable Diffusion** — image generation
2. **LLMs** — local text generation with CPU and GPU builds

It also includes:

- system prerequisites
- model download commands
- build steps
- runtime environment variables
- common errors and fixes

---

## System Prerequisites

Before building anything, prepare Termux with the required compilers, graphics headers, and Vulkan/driver packages.

```bash
pkg update && pkg upgrade -y
pkg install git cmake clang ninja

# Enable graphical and hardware-related repositories
pkg install x11-repo tur-repo

# Vulkan headers, shader compiler, and Mesa/Turnip support
pkg install vulkan-loader-generic vulkan-headers shaderc ndk-sysroot
pkg install mesa-vulkan-icd-freedreno-dri3


---

Part 1: Stable Diffusion

Image Generation on Android

On newer Snapdragon chips, GPU/Vulkan builds can sometimes trigger heavy memory spikes and crashes inside Termux.
For that reason, the CPU build is the most stable option for image generation.


---

1) Build the CPU Engine

git clone --recursive https://github.com/leejet/stable-diffusion.cpp
cd stable-diffusion.cpp
mkdir build && cd build

cmake .. -G Ninja -DSD_WEBP=OFF
cmake --build . --config Release
cd ..


---

2) Download the Model

A quantized GGUF model keeps memory usage practical on mobile while preserving good quality.

mkdir -p models

wget https://huggingface.co/second-state/stable-diffusion-v1-5-GGUF/resolve/main/stable-diffusion-v1-5-pruned-emaonly-Q4_0.gguf \
  -O models/sd-v1.5-q4.gguf


---

3) Generate an Image

./bin/sd-cli \
  -m models/sd-v1.5-q4.gguf \
  -p "a beautiful cyberpunk city at night, neon lights, flying cars, highly detailed, 4k masterpiece" \
  -n "blurry, ugly, noisy, pixelated, abstract, low resolution" \
  -H 512 -W 512 \
  -t 4 \
  --mmap \
  --sampling-method euler_a \
  --steps 15 \
  -o my_cyberpunk_city.png \
  -v


---

Part 2: Large Language Models

Llama 3.2, Qwen 2.5, and BitNet

This section uses a specialized llm.cpp fork that supports standard GGUF models and BitNet-style models.


---

1) Clone the Repository

cd ~
git clone https://github.com/tetherto/qvac-fabric-llm.cpp
cd qvac-fabric-llm.cpp
mkdir -p models


---

2) Download Models

Qwen 2.5 (1.5B)

wget https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf \
  -O models/qwen2.5-1.5b.gguf

Llama 3.2 (1B)

wget https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf \
  -O models/llama-3.2-1b.gguf

BitNet (1.58-bit)

wget https://huggingface.co/qvac/fabric-llm-finetune-bitnet/resolve/main/1bitLLM-bitnet_b1_58-xl-tq1_0.gguf \
  -O models/bitnet-xl.gguf


---

Build Option A: High-Speed CPU

Recommended for speed and stability

On Snapdragon 7 Gen 3, the CPU build with NEON support can be surprisingly fast for text generation.

mkdir build-cpu && cd build-cpu
cmake .. -G Ninja -DGGML_OPENMP=ON -DCMAKE_BUILD_TYPE=Release

# Fix Android tagged pointers crash during build/runtime
export ASAN_OPTIONS=detect_leaks=0

cmake --build . --config Release -j $(nproc)
cd ..

Run the model

./build-cpu/bin/llama-cli \
  -m models/qwen2.5-1.5b.gguf \
  -c 2048 \
  -t 5 \
  --temp 0.7 \
  -p "Explain the concept of cyberpunk to a time traveler from the year 1800."


---

Build Option B: GPU / Vulkan

Using Mesa Turnip drivers

This path is meant for Vulkan acceleration.
The reason for using Mesa Turnip is that official Android Adreno drivers can crash during complex shader compilation.

mkdir build-gpu && cd build-gpu

LDFLAGS="-L$PREFIX/lib" CPPFLAGS="-I$PREFIX/include" \
cmake .. -G Ninja -DGGML_VULKAN=ON -DGGML_OPENMP=ON -DCMAKE_BUILD_TYPE=Release

export ASAN_OPTIONS=detect_leaks=0

cmake --build . --config Release -j $(nproc)
cd ..


---

Run the GPU Build

Before launching, export the Vulkan driver path and library path.

# Point to the Turnip Vulkan driver
export VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json

# Point to the built binaries / libraries
export LD_LIBRARY_PATH=$HOME/qvac-fabric-llm.cpp/build-gpu/bin:$LD_LIBRARY_PATH

Check whether the GPU device is detected

./build-gpu/bin/llama-cli --list-devices

Run fully offloaded on GPU

./build-gpu/bin/llama-cli \
  -m models/qwen2.5-1.5b.gguf \
  -ngl 99 \
  -t 3 \
  -p "Hi"


---

Common Errors & Fixes

Segmentation fault during linking or runtime

Cause: Android’s memory tagging / pointer-related security behavior
Fix:

export ASAN_OPTIONS=detect_leaks=0

Use this before building or running the binaries.


---

Could NOT find Vulkan (missing: Vulkan_INCLUDE_DIR glslc)

Cause: Missing Vulkan headers or shader compiler
Fix:

pkg install vulkan-headers shaderc ndk-sysroot


---

Available devices: (List is empty) on GPU build

Cause: The binary cannot locate the Turnip driver
Fix: Make sure these are exported:

export VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json
export LD_LIBRARY_PATH=$HOME/qvac-fabric-llm.cpp/build-gpu/bin:$LD_LIBRARY_PATH


---

Phone freezes or reboots during Stable Diffusion

Cause: Adreno driver VRAM spike
Fix: Use the CPU build for image generation.


---

Notes

Use CPU mode for the most stable Stable Diffusion experience.

Use GPU/Vulkan mode only after confirming the driver setup is correct.

Lower thread counts may help on some devices when the GPU path is active.

Model performance depends heavily on device RAM, thermal limits, and driver stability.



---

Credits

This guide was assembled from real testing, troubleshooting, and build verification on Android.

If this helped you bring local AI to your Android device, consider starring the repository.


---

License
