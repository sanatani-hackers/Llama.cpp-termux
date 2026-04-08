#!/bin/bash

# ==============================================================================
# ENHANCED HARDWARE PROFILING ENGINE (Termux/Android - No Root)
# ==============================================================================

LOG_FILE="build_crash_log.txt"
rm -f $LOG_FILE

check_error() {
    if [ $? -ne 0 ]; then
        echo -e "\n${R}[!] FATAL ERROR OCCURRED!${N}"
        echo -e "${Y}Task Failed:${N} $1"
        echo -e "Log saved to: ${Y}$PWD/$LOG_FILE${N}"
        exit 1
    fi
}

detect_hardware() {
    local soc gpu_vendor gpu_type gpu_supported turnip_supported
    local cores ram_total ram_avail swap_total storage_avail
    local rec_threads cmake_extra_flags build_rec gpu_level
    
    # =========================================================================
    # 1. CPU ARCHITECTURE & CORE DETECTION (Termux compatible)
    # =========================================================================
    CORES=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "1")
    
    # Detect CPU architecture variant (ARMv8, ARMv8.2, ARMv9)
    CPU_ARCH=$(cat /proc/cpuinfo | grep -i "features" | head -1 2>/dev/null || echo "")
    if [[ "$CPU_ARCH" == *"asimd"* ]]; then
        CPU_VARIANT="ARMv8.0 (NEON)"
    elif [[ "$CPU_ARCH" == *"sve"* ]]; then
        CPU_VARIANT="ARMv8.2+ (SVE)"
    elif [[ "$CPU_ARCH" == *"fphp"* ]] || [[ "$CPU_ARCH" == *"asimdhp"* ]]; then
        CPU_VARIANT="ARMv8.2-A (Half-Precision)"
    else
        CPU_VARIANT="ARMv8.0-A (Generic)"
    fi
    
    # Detect CPU frequency (Termux may have limited access)
    MAX_CPU_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)
    if [ -z "$MAX_CPU_FREQ" ]; then
        MAX_CPU_FREQ_GHZ="Unknown"
    else
        MAX_CPU_FREQ_GHZ=$((MAX_CPU_FREQ / 1000000))
    fi
    
    # =========================================================================
    # 2. MEMORY PROFILING (Termux compatible - using /proc/meminfo)
    # =========================================================================
    if [ -f /proc/meminfo ]; then
        RAM_TOTAL=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 ))
        RAM_AVAIL=$(( $(grep MemAvailable /proc/meminfo | awk '{print $2}') / 1024 ))
    else
        RAM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")
        RAM_AVAIL=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || echo "0")
    fi
    
    SWAP_TOTAL=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}' || echo "0")
    
    # Check for ZRAM (compressed memory) - Termux may not have zramctl
    if command -v zramctl &>/dev/null; then
        ZRAM_TOTAL=$(zramctl 2>/dev/null | awk 'NR>1 {s+=$2} END {print s}' || echo "0")
        ZRAM_TOTAL_MB=$((ZRAM_TOTAL / 1048576))
    else
        ZRAM_TOTAL_MB=0
    fi
    
    # Effective RAM = Available RAM + Available SWAP + ZRAM headroom
    EFFECTIVE_RAM=$((RAM_AVAIL + SWAP_TOTAL + ZRAM_TOTAL_MB))
    if [ "$EFFECTIVE_RAM" -eq 0 ]; then
        EFFECTIVE_RAM=$((RAM_TOTAL / 2))
    fi
    
    # =========================================================================
    # 3. STORAGE I/O PERFORMANCE (Termux compatible)
    # =========================================================================
    STORAGE_AVAIL=$(df -h $PREFIX 2>/dev/null | tail -1 | awk '{print $4}')
    STORAGE_PATH="$PREFIX"
    
    if [ -z "$STORAGE_AVAIL" ]; then
        STORAGE_AVAIL=$(df -h /data 2>/dev/null | tail -1 | awk '{print $4}')
        STORAGE_PATH="/data"
    fi
    
    # Quick I/O performance test (write speed) - Termux friendly
    if [ -w /tmp ]; then
        IO_TEST=$(dd if=/dev/zero of=/tmp/io_test bs=1M count=10 conv=fdatasync 2>&1 | grep "bytes" | awk '{print $8}' || echo "Unknown")
        rm -f /tmp/io_test
    else
        IO_TEST="Unknown"
    fi
    
    # =========================================================================
    # 4. GPU & SoC DETECTION (FIXED FOR SM-PREFIX)
    # =========================================================================
    SOC=$(getprop ro.soc.model 2>/dev/null || \
          getprop ro.board.platform 2>/dev/null || \
          getprop ro.hardware 2>/dev/null || \
          echo "unknown")
    SOC=$(echo "$SOC" | tr '[:upper:]' '[:lower:]')
    
    # Primary GPU vendor detection via getprop
    GPU_VENDOR=$(getprop ro.hardware.egl 2>/dev/null || \
                 getprop ro.hardware.vulkan 2>/dev/null || \
                 echo "unknown")
    GPU_VENDOR=$(echo "$GPU_VENDOR" | tr '[:upper:]' '[:lower:]')
    
    # Secondary: Check Vulkan ICD files in Termux prefix
    if [ -f "$PREFIX/share/vulkan/icd.d/adreno_icd.aarch64.json" ] 2>/dev/null; then
        GPU_VENDOR="adreno"
    elif [ -f "$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json" ] 2>/dev/null; then
        GPU_VENDOR="freedreno"
    fi
    
    # =========================================================================
    # 5. GPU CLASSIFICATION - WITH SM-PREFIX DETECTION (FIXED)
    # =========================================================================
    GPU_SUPPORTED=false
    TURNIP_SUPPORTED=false
    GPU_LEVEL="UNKNOWN"
    GPU_TYPE="Unknown"
    GPU_VRAM_EST=0
    
    # FIRST: Detect by SM prefix (Qualcomm's internal naming)
    if [[ "$SOC" == sm* ]] || [[ "$SOC" == *"sm"* ]]; then
        # Extract SM number
        SM_NUM=$(echo "$SOC" | grep -oE 'sm[0-9]{4}' | head -1)
        
        case "$SM_NUM" in
            # 8 Gen Series (Premium)
            sm8650|sm8655|sm8550|sm8475|sm8450|sm8350|sm8250|sm8150)
                GPU_SUPPORTED=true
                TURNIP_SUPPORTED=true
                GPU_LEVEL="PREMIUM"
                GPU_TYPE="Adreno Premium (8 Gen Series - $SM_NUM)"
                GPU_VRAM_EST=8192
                ;;
            # 7 Gen Series (High-End) - YOUR sm7550 FALLS HERE
            sm7550|sm7475|sm7450|sm7350|sm7325|sm7250|sm7225|sm7150|sm7125|sm7115)
                GPU_SUPPORTED=true
                TURNIP_SUPPORTED=true
                GPU_LEVEL="HIGH"
                GPU_TYPE="Adreno High-End (7 Gen Series - $SM_NUM)"
                GPU_VRAM_EST=6144
                ;;
            # 6 Gen Series (Mid-High)
            sm6375|sm6350|sm6225|sm6125|sm6115|sm6105)
                GPU_SUPPORTED=true
                TURNIP_SUPPORTED=true
                GPU_LEVEL="MID_HIGH"
                GPU_TYPE="Adreno Mid-High (6 Gen Series - $SM_NUM)"
                GPU_VRAM_EST=4096
                ;;
            # 4 Gen Series (Mid)
            sm4450|sm4375|sm4350|sm4250|sm4150)
                GPU_SUPPORTED=true
                TURNIP_SUPPORTED=true
                GPU_LEVEL="MID"
                GPU_TYPE="Adreno Mid (4 Gen Series - $SM_NUM)"
                GPU_VRAM_EST=2048
                ;;
            *)
                # Unknown SM but still Snapdragon
                GPU_SUPPORTED=true
                TURNIP_SUPPORTED=true
                GPU_LEVEL="MID"
                GPU_TYPE="Adreno Snapdragon ($SM_NUM)"
                GPU_VRAM_EST=4096
                ;;
        esac
    fi
    
    # SECOND: Detect by SOC name patterns (if SM detection didn't trigger)
    if [ "$GPU_SUPPORTED" = false ]; then
        # Qualcomm Snapdragon by name
        if [[ "$SOC" == *"qcom"* ]] || [[ "$SOC" == *"snapdragon"* ]] || [[ "$GPU_VENDOR" == *"adreno"* ]]; then
            GPU_SUPPORTED=true
            TURNIP_SUPPORTED=true
            
            # Adreno GPU variant detection
            if [[ "$SOC" == *"8gen"* ]] || [[ "$SOC" == *"8 gen"* ]]; then
                GPU_TYPE="Adreno 8 Series (Premium)"
                GPU_LEVEL="PREMIUM"
                GPU_VRAM_EST=8192
            elif [[ "$SOC" == *"7gen"* ]] || [[ "$SOC" == *"7 gen"* ]] || [[ "$SOC" == *"780"* ]] || [[ "$SOC" == *"778"* ]]; then
                GPU_TYPE="Adreno 7 Series (High-End)"
                GPU_LEVEL="HIGH"
                GPU_VRAM_EST=6144
            elif [[ "$SOC" == *"888"* ]] || [[ "$SOC" == *"870"* ]] || [[ "$SOC" == *"865"* ]]; then
                GPU_TYPE="Adreno 600 Series (High)"
                GPU_LEVEL="HIGH"
                GPU_VRAM_EST=6144
            elif [[ "$SOC" == *"855"* ]] || [[ "$SOC" == *"845"* ]]; then
                GPU_TYPE="Adreno 600 Series (Mid-High)"
                GPU_LEVEL="MID_HIGH"
                GPU_VRAM_EST=4096
            else
                GPU_TYPE="Adreno Snapdragon"
                GPU_LEVEL="MID"
                GPU_VRAM_EST=2048
            fi
        
        # MediaTek Detection
        elif [[ "$SOC" == *"dimensity"* ]] || [[ "$SOC" == *"helio"* ]] || [[ "$GPU_VENDOR" == *"mali"* ]]; then
            if [[ "$SOC" == *"9300"* ]] || [[ "$SOC" == *"9200"* ]] || [[ "$SOC" == *"9000"* ]]; then
                GPU_TYPE="Mali-G715/G720 (Dimensity Premium)"
                GPU_LEVEL="PREMIUM"
                GPU_SUPPORTED=true
                GPU_VRAM_EST=6144
            elif [[ "$SOC" == *"8300"* ]] || [[ "$SOC" == *"8200"* ]] || [[ "$SOC" == *"8100"* ]] || [[ "$SOC" == *"8000"* ]]; then
                GPU_TYPE="Mali-G610/G710 (Dimensity High)"
                GPU_LEVEL="HIGH"
                GPU_SUPPORTED=true
                GPU_VRAM_EST=4096
            elif [[ "$SOC" == *"helio"* ]]; then
                GPU_TYPE="Mali/PowerVR (Helio)"
                GPU_LEVEL="MID"
                GPU_SUPPORTED=true
                GPU_VRAM_EST=2048
            else
                GPU_TYPE="Mali (MediaTek)"
                GPU_LEVEL="MID"
                GPU_SUPPORTED=true
                GPU_VRAM_EST=2048
            fi
        
        # Exynos Detection
        elif [[ "$SOC" == *"exynos"* ]]; then
            if [[ "$SOC" == *"2400"* ]] || [[ "$SOC" == *"2200"* ]]; then
                GPU_TYPE="Xclipse (Exynos Premium)"
                GPU_LEVEL="PREMIUM"
                GPU_SUPPORTED=true
                GPU_VRAM_EST=6144
            else
                GPU_TYPE="Mali (Exynos)"
                GPU_LEVEL="HIGH"
                GPU_SUPPORTED=true
                GPU_VRAM_EST=4096
            fi
        
        # Unsupported / PowerVR
        elif [[ "$GPU_VENDOR" == *"powervr"* ]]; then
            GPU_TYPE="PowerVR (Unsupported)"
            GPU_LEVEL="UNSUPPORTED"
            GPU_SUPPORTED=false
            GPU_VRAM_EST=512
        
        # Fallback - but check if we can detect via /proc/cpuinfo
        else
            # Try to detect from /proc/cpuinfo
            CPUINFO_HARDWARE=$(cat /proc/cpuinfo | grep -i "hardware" | head -1 | cut -d: -f2 | tr -d ' ' 2>/dev/null)
            if [[ "$CPUINFO_HARDWARE" == *"qcom"* ]] || [[ "$CPUINFO_HARDWARE" == *"snapdragon"* ]]; then
                GPU_SUPPORTED=true
                TURNIP_SUPPORTED=true
                GPU_TYPE="Adreno (Detected via /proc/cpuinfo)"
                GPU_LEVEL="MID"
                GPU_VRAM_EST=4096
            else
                GPU_TYPE="Unknown / Integrated"
                GPU_LEVEL="UNKNOWN"
                GPU_SUPPORTED=false
                GPU_VRAM_EST=1024
            fi
        fi
    fi
    
    # =========================================================================
    # 6. THREAD & OPTIMIZATION RECOMMENDATIONS (Termux optimized)
    # =========================================================================
    
    # Conservative thread allocation based on RAM & GPU
    if [ "$EFFECTIVE_RAM" -lt 2500 ]; then
        REC_THREADS=2
        BATCH_SIZE=32
    elif [ "$EFFECTIVE_RAM" -lt 4500 ]; then
        REC_THREADS=$((CORES > 4 ? 4 : CORES))
        BATCH_SIZE=64
    elif [ "$EFFECTIVE_RAM" -lt 8000 ]; then
        REC_THREADS=$((CORES - 1))
        BATCH_SIZE=128
    else
        REC_THREADS=$CORES
        BATCH_SIZE=256
    fi
    
    # Ensure at least 1 thread
    [ "$REC_THREADS" -lt 1 ] && REC_THREADS=1
    
    # GPU-specific optimizations
    case "$GPU_LEVEL" in
        PREMIUM)
            CMAKE_EXTRA_FLAGS="-DGGML_VULKAN=ON -DGGML_OPENMP=ON"
            BUILD_REC="GPU Vulkan (Maximum Performance)"
            CONTEXT_SIZE=4096
            ;;
        HIGH)
            CMAKE_EXTRA_FLAGS="-DGGML_VULKAN=ON -DGGML_OPENMP=ON"
            BUILD_REC="GPU Vulkan (High Performance)"
            CONTEXT_SIZE=2048
            ;;
        MID_HIGH)
            CMAKE_EXTRA_FLAGS="-DGGML_VULKAN=ON"
            BUILD_REC="GPU Vulkan (Balanced)"
            CONTEXT_SIZE=1024
            ;;
        MID)
            if [ "$GPU_SUPPORTED" = true ]; then
                CMAKE_EXTRA_FLAGS="-DGGML_VULKAN=ON"
                BUILD_REC="GPU Vulkan (Experimental)"
                CONTEXT_SIZE=512
            else
                CMAKE_EXTRA_FLAGS="-DGGML_OPENMP=ON"
                BUILD_REC="CPU-Only (Stable)"
                CONTEXT_SIZE=512
            fi
            ;;
        LOW|UNSUPPORTED)
            CMAKE_EXTRA_FLAGS=""
            BUILD_REC="CPU-Only (Low-End Optimized)"
            CONTEXT_SIZE=256
            REC_THREADS=$((CORES > 2 ? 2 : CORES))
            BATCH_SIZE=16
            ;;
        *)
            CMAKE_EXTRA_FLAGS="-DGGML_OPENMP=ON"
            BUILD_REC="CPU-Only (Safe Fallback)"
            CONTEXT_SIZE=512
            ;;
    esac
    
    # =========================================================================
    # 7. EXPORT ALL VARIABLES
    # =========================================================================
    export CORES RAM_TOTAL RAM_AVAIL SWAP_TOTAL ZRAM_TOTAL_MB EFFECTIVE_RAM
    export STORAGE_AVAIL STORAGE_PATH IO_TEST
    export SOC CPU_VARIANT CPU_ARCH MAX_CPU_FREQ_GHZ
    export GPU_VENDOR GPU_TYPE GPU_LEVEL GPU_SUPPORTED TURNIP_SUPPORTED GPU_VRAM_EST
    export REC_THREADS CMAKE_EXTRA_FLAGS BUILD_REC BATCH_SIZE CONTEXT_SIZE
}

# ==============================================================================
# DISPLAY DETAILED HARDWARE REPORT
# ==============================================================================

display_hardware_report() {
    # Colors
    local G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' R='\033[0;31m' N='\033[0m'
    
    echo -e "\n${C}════════════════════════════════════════════════════════${N}"
    echo -e "${G}          COMPREHENSIVE HARDWARE PROFILE               ${N}"
    echo -e "${C}════════════════════════════════════════════════════════${N}\n"
    
    # CPU Section
    echo -e "${Y}📱 CPU / PROCESSOR${N}"
    echo -e "  SoC Model              : ${G}$SOC${N}"
    echo -e "  Architecture           : ${G}$CPU_VARIANT${N}"
    echo -e "  Physical Cores         : ${G}$CORES${N}"
    echo -e "  Max Clock Speed        : ${G}${MAX_CPU_FREQ_GHZ} GHz${N}"
    echo -e "  Recommended Threads    : ${Y}$REC_THREADS${N}"
    
    # Memory Section
    echo -e "\n${Y}🧠 MEMORY SYSTEM${N}"
    echo -e "  RAM Available          : ${G}${RAM_AVAIL} MB${N} / ${RAM_TOTAL} MB Total"
    echo -e "  SWAP Available         : ${G}${SWAP_TOTAL} MB${N}"
    echo -e "  ZRAM (Compressed)      : ${G}${ZRAM_TOTAL_MB} MB${N}"
    echo -e "  Effective Memory Pool  : ${Y}${EFFECTIVE_RAM} MB${N} (RAM + SWAP + ZRAM)"
    
    # Storage Section
    echo -e "\n${Y}💾 STORAGE${N}"
    echo -e "  Mount Path             : ${G}$STORAGE_PATH${N}"
    echo -e "  Available Space        : ${G}$STORAGE_AVAIL${N}"
    echo -e "  I/O Performance        : ${G}${IO_TEST} MB/s${N}"
    
    # GPU Section
    echo -e "\n${Y}🎮 GPU / GRAPHICS${N}"
    echo -e "  GPU Type               : ${G}$GPU_TYPE${N}"
    echo -e "  GPU Tier               : ${Y}$GPU_LEVEL${N}"
    echo -e "  Estimated VRAM         : ${G}${GPU_VRAM_EST} MB${N}"
    
    if [ "$GPU_SUPPORTED" = true ]; then
        echo -e "  Vulkan Support         : ${G}✓ YES${N}"
    else
        echo -e "  Vulkan Support         : ${R}✗ NO${N}"
    fi
    
    if [ "$TURNIP_SUPPORTED" = true ]; then
        echo -e "  Turnip (Open-Source)   : ${G}✓ YES${N} (Recommended for Adreno)"
    else
        echo -e "  Turnip (Open-Source)   : ${R}✗ NO${N}"
    fi
    
    # Build Recommendation Section
    echo -e "\n${Y}⚙️  BUILD RECOMMENDATION${N}"
    echo -e "  Optimal Strategy       : ${Y}$BUILD_REC${N}"
    echo -e "  Batch Size             : ${G}$BATCH_SIZE${N}"
    echo -e "  Context Length         : ${G}$CONTEXT_SIZE tokens${N}"
    echo -e "  CMake Flags            : ${C}$CMAKE_EXTRA_FLAGS${N}"
    
    echo -e "\n${C}════════════════════════════════════════════════════════${N}\n"
}

# ==============================================================================
# DETAILED COMPATIBILITY CHECK
# ==============================================================================

compatibility_check() {
    local G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' R='\033[0;31m' N='\033[0m'
    
    echo -e "${Y}[*] Running Compatibility Tests...${N}\n"
    
    local issues_found=0
    
    # Test 1: RAM Check
    if [ "$EFFECTIVE_RAM" -lt 1500 ]; then
        echo -e "${R}[!] WARNING: Very low memory (${EFFECTIVE_RAM} MB)${N}"
        echo -e "    Recommendation: Use quantized models (q2_k, q3_k)"
        echo -e "    or reduce context size to 256 tokens\n"
        ((issues_found++))
    elif [ "$EFFECTIVE_RAM" -lt 2500 ]; then
        echo -e "${Y}[!] LOW MEMORY: ${EFFECTIVE_RAM} MB available${N}"
        echo -e "    Recommendation: Use q3_k or q4_k quantization\n"
        ((issues_found++))
    else
        echo -e "${G}[✓] RAM Check: PASS (${EFFECTIVE_RAM} MB available)${N}\n"
    fi
    
    # Test 2: Storage Check
    STORAGE_AVAIL_INT=$(echo "$STORAGE_AVAIL" | sed 's/G$//' | sed 's/M$//' | sed 's/[^0-9]//g')
    if [[ "$STORAGE_AVAIL" == *"G"* ]]; then
        STORAGE_AVAIL_INT=$((STORAGE_AVAIL_INT * 1024))
    fi
    
    if [ -n "$STORAGE_AVAIL_INT" ] && [ "$STORAGE_AVAIL_INT" -lt 1024 ] 2>/dev/null; then
        echo -e "${R}[!] LOW STORAGE: Only ${STORAGE_AVAIL} available${N}"
        echo -e "    Recommendation: Free up space (models need 2-5 GB)\n"
        ((issues_found++))
    else
        echo -e "${G}[✓] Storage Check: PASS (${STORAGE_AVAIL} available)${N}\n"
    fi
    
    # Test 3: GPU Stability Check
    if [ "$GPU_SUPPORTED" = true ] && [ "$TURNIP_SUPPORTED" = false ]; then
        echo -e "${Y}[!] GPU WARNING: Vulkan driver may be unstable on $GPU_TYPE${N}"
        echo -e "    Recommendation: Test with CPU build first, then enable GPU gradually\n"
        ((issues_found++))
    fi
    
    # Test 4: CPU Architecture Check
    if [[ "$CPU_VARIANT" == *"ARMv8.0"* ]]; then
        echo -e "${Y}[!] OLDER CPU: Using legacy ARMv8.0 architecture${N}"
        echo -e "    Recommendation: Use -march=armv8-a flag for broader compatibility\n"
        ((issues_found++))
    else
        echo -e "${G}[✓] CPU Architecture: GOOD ($CPU_VARIANT)${N}\n"
    fi
    
    # Summary
    if [ $issues_found -eq 0 ]; then
        echo -e "${G}[✓] ALL CHECKS PASSED - Ready for optimal build!${N}\n"
    else
        echo -e "${Y}[!] $issues_found potential issue(s) detected - see recommendations above${N}\n"
    fi
}

# ==============================================================================
# MODEL RECOMMENDATION ENGINE (SIMPLIFIED - Only Qwen & Llama)
# ==============================================================================

recommend_models() {
    local G='\033[0;32m' Y='\033[1;33m' C='\033[0;36m' R='\033[0;31m' N='\033[0m'
    
    echo -e "\n${C}════════════════════════════════════════════════════════${N}"
    echo -e "${Y}🤖 MODEL RECOMMENDATIONS FOR YOUR HARDWARE${N}"
    echo -e "${C}════════════════════════════════════════════════════════${N}\n"
    
    case "$GPU_LEVEL" in
        PREMIUM)
            echo -e "${G}PREMIUM TIER (GPU Acceleration Recommended)${N}"
            echo -e "  • ${Y}Qwen 2.5 72B (q5_k_m)${N} - 41 GB | 15-20 tok/s"
            echo -e "  • ${Y}Llama 2 70B (q4_k_m)${N} - 38 GB | 15-18 tok/s"
            ;;
        HIGH)
            echo -e "${G}HIGH-END TIER${N}"
            echo -e "  • ${Y}Qwen 2.5 14B (q5_k_m)${N} - 8.5 GB | 10-15 tok/s"
            echo -e "  • ${Y}Llama 2 13B (q5_k_m)${N} - 8 GB | 8-12 tok/s"
            echo -e "  • ${Y}Qwen 2.5 7B (q6_k)${N} - 5 GB | 12-18 tok/s"
            ;;
        MID_HIGH)
            echo -e "${G}MID-HIGH TIER${N}"
            echo -e "  • ${Y}Qwen 2.5 7B (q4_k_m)${N} - 4.2 GB | 6-10 tok/s ⭐"
            echo -e "  • ${Y}Llama 2 7B (q5_k_m)${N} - 4.2 GB | 5-8 tok/s"
            ;;
        MID)
            echo -e "${Y}MID TIER${N}"
            echo -e "  • ${Y}Qwen 2.5 3B (q4_k_m)${N} - 2 GB | 3-6 tok/s ⭐"
            echo -e "  • ${Y}Llama 2 7B (q2_k)${N} - 2.5 GB | 2-4 tok/s"
            ;;
        LOW|UNSUPPORTED)
            echo -e "${Y}LOW-END TIER (CPU-Only)${N}"
            echo -e "  • ${Y}Qwen 2.5 1.5B (q3_k_m)${N} - 1.1 GB | 2-4 tok/s ⭐"
            echo -e "  • ${Y}Qwen 2.5 0.5B (q4_k_m)${N} - 350 MB | 4-8 tok/s"
            ;;
    esac
    
    echo -e "\n${C}════════════════════════════════════════════════════════${N}\n"
}

# Run detection and display
detect_hardware
display_hardware_report
compatibility_check
recommend_models

# Rest of your installer script continues here...
# (The build options, compilation, and model downloader remain the same)
# ==============================================================================
# INTERACTIVE MENU (UPDATED)
# ==============================================================================

#echo -e "\n${C}=====================================================${N}"
#echo -e "Select Build Option:"
#echo -e "1) Auto-Tune CPU Build (Safe & Stable)"

#if [ "$GPU_SUPPORTED" = true ]; then
#    echo -e "2) GPU Vulkan Build (${GPU_LEVEL} - Recommended for $GPU_TYPE)"
#else
#    echo -e "${R}2) GPU Vulkan Build (DISABLED - $GPU_TYPE not supported)${N}"
#fi
#
#if [ "$TURNIP_SUPPORTED" = true ]; then
#    echo -e "3) Turnip Open-Source Build (Adreno - Maximum Speed)"else
#    echo -e "${R}3) Turnip Build (DISABLED - Requires Snapdragon/Adreno)${N}"
#fi

#echo -e "4) Universal ARMv8.2-a Cross-Compile (Compatibility Mode)"
#echo -e "5) Skip Build → Auto-Download Recommended Model"
#echo -e "6) Exit"
#echo -e "${C}=====================================================${N}"

#read -p "Enter choice [1-6]: " choice

echo -e "\n${C}=====================================================${N}"
echo -e "Select Installation Method:"
echo -e "${Y}--- FAST INSTALL (Pre-Built Binaries) ---${N}"
echo -e "1) Install Pre-Built Engine (Auto-Detects Best Version)"
echo -e "\n${Y}--- COMPILE FROM SOURCE (Advanced) ---${N}"
echo -e "2) Auto-Tune CPU Build (Safe & Stable)"
if [ "$GPU_SUPPORTED" = true ]; then echo -e "3) GPU Vulkan Build (${GPU_LEVEL})"; else echo -e "${R}3) GPU Vulkan Build (DISABLED)${N}"; fi
if [ "$TURNIP_SUPPORTED" = true ]; then echo -e "4) Turnip Open-Source Build (Adreno)"; else echo -e "${R}4) Turnip Build (DISABLED)${N}"; fi
echo -e "5) Universal ARMv8.2-a Cross-Compile"
echo -e "\n${Y}--- OTHER ---${N}"
echo -e "6) Skip Build → Auto-Download Recommended Model"
echo -e "7) Exit"
echo -e "${C}=====================================================${N}"

read -p "Enter choice [1-7]: " choice

# Safety blocks for disabled options
if [ "$choice" == "2" ] && [ "$GPU_SUPPORTED" = false ]; then
    echo -e "${R}[!] GPU Build is disabled for your hardware ($GPU_TYPE).${N}"
    echo -e "${Y}Falling back to CPU-only build...${N}"
    choice=1
fi

if [ "$choice" == "3" ] && [ "$TURNIP_SUPPORTED" = false ]; then
    echo -e "${R}[!] Turnip requires an Adreno GPU.${N}"
    echo -e "${Y}Using standard GPU build instead...${N}"
    choice=2
fi

if [ "$choice" == "6" ]; then exit 0; fi

# ==============================================================================
# PRE-BUILT BINARY DOWNLOADER
# ==============================================================================
install_prebuilt() {
    local build_variant=$1 # Expects: "cpu", "vulkan", or "turnip"
    local gh_user="sanatani-hackers" # Change this!
    local repo_name="Llama.cpp-termux"
    
    echo -e "\n${Y}[*] Querying GitHub for the latest release...${N}"
    
    # Fetch the latest release tag using GitHub's public API
    LATEST_TAG=$(curl -s "https://api.github.com/repos/$gh_user/$repo_name/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [ -z "$LATEST_TAG" ]; then
        echo -e "${R}[!] Failed to fetch release data. Check if your repository is public and has a 'Release' published.${N}"
        exit 1
    fi
    
    echo -e "${G}[+] Found latest stable version: ${C}${LATEST_TAG}${N}"
    
    # Construct the download URL based on the variant
    local tarball="bitnet-${build_variant}-android.tar.gz"
    local download_url="https://github.com/$gh_user/$repo_name/releases/download/$LATEST_TAG/$tarball"
    
    echo -e "${Y}[*] Downloading ${tarball}...${N}"
    mkdir -p "$PREFIX/tmp"
    
    # Download the file
    wget --show-progress -qO "$PREFIX/tmp/$tarball" "$download_url"
    check_error "Downloading $tarball (Check if the file exists on your GitHub Release)"
    
    echo -e "${Y}[*] Extracting binaries to $INSTALL_DIR...${N}"
    mkdir -p "$INSTALL_DIR"
    
    # Extract the tarball directly into the installation directory
    tar -xzf "$PREFIX/tmp/$tarball" -C "$INSTALL_DIR"
    check_error "Extracting binaries from $tarball"
    
    # Clean up the temp file
    rm -f "$PREFIX/tmp/$tarball"
    
    echo -e "${G}[✓] Pre-built ${build_variant} engine installed successfully!${N}"
}

# ==============================================================================
# DEPENDENCIES & CLONING
# ==============================================================================

if [[ "$choice" =~ ^[1-4]$ ]]; then
    echo -e "\n${Y}[*] Installing Common Dependencies...${N}"
    apt update -y && apt install clang cmake ninja wget git -y
    check_error "Installing dependencies"

    if [ ! -d "qvac-fabric-llm.cpp" ]; then
        echo -e "${Y}[*] Cloning Repository...${N}"
        git clone --depth=1 "https://github.com/tetherto/qvac-fabric-llm.cpp"
        check_error "Cloning git repository"
    fi
    cd qvac-fabric-llm.cpp || exit
    export ASAN_OPTIONS=detect_leaks=0
fi

# ==============================================================================
# COMPILATION LOGIC AMD PRE-BUILT BINARY DOWNLOAD (ENHANCED)
# ==============================================================================

if [ "$choice" == "1" ]; then
    # Make sure we have curl to query the API
    apt update -y && apt install curl wget -y >/dev/null 2>&1
    
    # Auto-detect which binary to fetch based on previous hardware profiling
    if [ "$choice" == "1" ]; then
        if [ "$TURNIP_SUPPORTED" = true ]; then
            install_prebuilt "turnip"
        elif [ "$GPU_SUPPORTED" = true ]; then
            install_prebuilt "vulkan"
        else
            install_prebuilt "cpu"
        fi
    fi
    
    # Skip the massive git clone and cmake build steps by telling the script we are done building!
    BUILD_DIR="prebuilt" 

elif [ "$choice" == "2" ]; then
    echo -e "${G}[*] Building CPU Engine (${REC_THREADS} threads)...${N}"
    mkdir -p build && cd build
    cmake .. -G Ninja -DGGML_OPENMP=ON -DCMAKE_BUILD_TYPE=Release $CMAKE_EXTRA_FLAGS
    check_error "CMake Configuration (CPU)"
    cmake --build . --config Release -j $REC_THREADS
    check_error "Compilation (CPU)"

elif [ "$choice" == "3" ]; then
    echo -e "${Y}[*] Installing GPU Vulkan Stack for ${GPU_TYPE}...${N}"
    apt install vulkan-headers vulkan-loader-generic shaderc -y
    check_error "Installing Vulkan packages"

    echo -e "${G}[*] Building GPU Vulkan Engine (${REC_THREADS} threads)...${N}"
    mkdir -p build-gpu && cd build-gpu
    cmake .. -G Ninja -DGGML_VULKAN=ON -DGGML_OPENMP=ON -DCMAKE_BUILD_TYPE=Release $CMAKE_EXTRA_FLAGS
    check_error "CMake Configuration (GPU Vulkan)"
    cmake --build . --config Release -j $REC_THREADS
    check_error "Compilation (GPU Vulkan)"

elif [ "$choice" == "4" ]; then
    echo -e "${Y}[*] Installing Turnip Open-Source Drivers (Freedreno)...${N}"
    apt install mesa-vulkan-icd-freedreno vulkan-loader-generic shaderc -y
    check_error "Installing Turnip/Freedreno packages"

    echo -e "${G}[*] Building Turnip GPU Engine (${REC_THREADS} threads)...${N}"
    mkdir -p build-turnip && cd build-turnip
    cmake .. -G Ninja -DGGML_VULKAN=ON -DGGML_OPENMP=ON -DCMAKE_BUILD_TYPE=Release $CMAKE_EXTRA_FLAGS
    check_error "CMake Configuration (Turnip GPU)"
    cmake --build . --config Release -j $REC_THREADS
    check_error "Compilation (Turnip GPU)"

elif [ "$choice" == "5" ]; then
    echo -e "${G}[*] Building Universal ARMv8.2-a Cross-Compile...${N}"
    mkdir -p build-universal && cd build-universal
    cmake .. -G Ninja -DGGML_OPENMP=ON -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="-march=armv8.2-a -mtune=generic" \
        -DCMAKE_CXX_FLAGS="-march=armv8.2-a -mtune=generic"
    check_error "CMake Configuration (Universal)"
    cmake --build . --config Release -j $REC_THREADS
    check_error "Compilation (Universal)"
fi

# ==============================================================================
# 6. GLOBAL INSTALLATION & PATH INJECTION
# ==============================================================================

if [[ "$choice" =~ ^[1-4]$ ]]; then
    echo -e "\n${Y}[*] Installing globally to $INSTALL_DIR...${N}"
    mkdir -p "$INSTALL_DIR/models"
    mkdir -p "$PREFIX/bin"

    # Detect build directory
    BUILD_DIR=""
    if [ "$choice" == "1" ]; then
        BUILD_DIR="build"
    elif [ "$choice" == "2" ]; then
        BUILD_DIR="build-gpu"
    elif [ "$choice" == "3" ]; then
        BUILD_DIR="build-turnip"
    elif [ "$choice" == "4" ]; then
        BUILD_DIR="build-universal"
    fi

    # Copy binaries safely
    if [ -d "$BUILD_DIR" ]; then
        cp "$BUILD_DIR/bin/llama-cli" "$INSTALL_DIR/" 2>/dev/null || cp "$BUILD_DIR/llama-cli" "$INSTALL_DIR/" 2>/dev/null
        cp "$BUILD_DIR/bin/libllama.so"* "$INSTALL_DIR/" 2>/dev/null || cp "$BUILD_DIR/libllama.so"* "$INSTALL_DIR/" 2>/dev/null
        cp "$BUILD_DIR/bin/llama-server" "$INSTALL_DIR/" 2>/dev/null || cp "$BUILD_DIR/llama-server" "$INSTALL_DIR/" 2>/dev/null
    fi
    check_error "Copying compiled binaries"

    # Create Wrapper Script with Enhanced Environment
    WRAPPER="$PREFIX/bin/bitnet"
    echo '#!/bin/bash' > $WRAPPER
    echo "# BitNet Wrapper - Auto-generated" >> $WRAPPER
    echo "export LD_LIBRARY_PATH=$INSTALL_DIR:\$LD_LIBRARY_PATH" >> $WRAPPER
    echo "export GGML_NUM_THREADS=$REC_THREADS" >> $WRAPPER
    echo "export GGML_BATCH=$BATCH_SIZE" >> $WRAPPER

    if [ "$choice" == "3" ]; then
        # TURNIP INJECTION (Freedreno)
        echo "# Turnip/Freedreno GPU Configuration" >> $WRAPPER
        echo "export VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json" >> $WRAPPER
        echo "export VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation" >> $WRAPPER
        echo "$INSTALL_DIR/llama-cli -ngl 99 -t $REC_THREADS \"\$@\"" >> $WRAPPER
        echo -e "${G}[+] Turnip GPU enabled (VK_ICD pointing to Freedreno)${N}"
    elif [ "$choice" == "2" ]; then
        # STANDARD GPU (Factory Vulkan)
        echo "# Standard Vulkan GPU Configuration" >> $WRAPPER
        echo "$INSTALL_DIR/llama-cli -ngl 99 -t $REC_THREADS \"\$@\"" >> $WRAPPER
        echo -e "${G}[+] Standard GPU acceleration enabled${N}"
    else
        # CPU ONLY
        echo "# CPU-Only Configuration" >> $WRAPPER
        echo "$INSTALL_DIR/llama-cli -t $REC_THREADS \"\$@\"" >> $WRAPPER
        echo -e "${G}[+] CPU-only mode activated (${REC_THREADS} threads)${N}"
    fi

    chmod +x $WRAPPER
    check_error "Creating global command wrapper"

    echo -e "\n${C}════════════════════════════════════════════════════════${N}"
    echo -e "${G}[✓] INSTALLATION SUCCESSFUL!${N}"
    echo -e "${C}════════════════════════════════════════════════════════${N}\n"
    echo -e "📍 Installation Directory: ${Y}$INSTALL_DIR${N}"
    echo -e "🔧 Command Wrapper: ${Y}bitnet${N}"
    echo -e "📊 Configuration:"
    echo -e "   • Threads: ${G}$REC_THREADS${N}"
    echo -e "   • Batch Size: ${G}$BATCH_SIZE${N}"
    echo -e "   • Context Length: ${G}$CONTEXT_SIZE tokens${N}"
    echo -e "   • Build Type: ${Y}$BUILD_REC${N}"

    # Navigate back out of the repo for the model downloader
    cd ..
fi

# ==============================================================================
# 7. INTELLIGENT MODEL DOWNLOADER (SIMPLIFIED - Only Qwen & Llama)
# ==============================================================================

echo -e "\n${C}════════════════════════════════════════════════════════${N}"
echo -e "${Y}Would you like to auto-download a model?${N}"
echo -e "${C}════════════════════════════════════════════════════════${N}\n"

echo -e "Available Models (Recommended for your hardware):\n"

# Simple model selection based on GPU level
case "$GPU_LEVEL" in
    PREMIUM)
        echo -e "1) ${G}Qwen 2.5 72B (q5_k_m)${N} - 41 GB (Premium LLM)"
        echo -e "2) ${G}Llama 2 70B (q4_k_m)${N} - 38 GB (Full-fat Model)"
        ;;
    HIGH)
        echo -e "1) ${G}Qwen 2.5 14B (q5_k_m)${N} - 8.5 GB (High-End)"
        echo -e "2) ${G}Llama 2 13B (q5_k_m)${N} - 8 GB (Balanced)"
        ;;
    MID_HIGH)
        echo -e "1) ${G}Qwen 2.5 7B (q4_k_m)${N} - 4.2 GB (⭐ Recommended)"
        echo -e "2) ${G}Llama 2 7B (q5_k_m)${N} - 4.2 GB (Quality)"
        ;;
    MID)
        echo -e "1) ${G}Qwen 2.5 3B (q4_k_m)${N} - 2 GB (⭐ Recommended)"
        echo -e "2) ${G}Llama 2 7B (q2_k)${N} - 2.5 GB (Lightweight)"
        ;;
    LOW|UNSUPPORTED)
        echo -e "1) ${G}Qwen 2.5 1.5B (q3_k_m)${N} - 1.1 GB (⭐ Recommended)"
        echo -e "2) ${G}Qwen 2.5 0.5B (q4_k_m)${N} - 350 MB (Ultra-Light)"
        ;;
esac

echo -e "3) ${Y}Custom Model (Provide HuggingFace link)${N}"
echo -e "4) Skip Download"
echo -e "${C}════════════════════════════════════════════════════════${N}"

read -p "Enter choice [1-4]: " dl_choice

mkdir -p "$INSTALL_DIR/models"

# Model download URLs (Only Qwen and Llama)
declare -A MODEL_URLS=(
    # Qwen Models
    ["qwen72b"]="https://huggingface.co/Qwen/Qwen2.5-72B-Instruct-GGUF/resolve/main/qwen2.5-72b-instruct-q5_k_m.gguf"
    ["qwen14b"]="https://huggingface.co/Qwen/Qwen2.5-14B-Instruct-GGUF/resolve/main/qwen2.5-14b-instruct-q5_k_m.gguf"
    ["qwen7b"]="https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/main/qwen2.5-7b-instruct-q4_k_m.gguf"
    ["qwen3b"]="https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf"
    ["qwen1.5b"]="https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q3_k_m.gguf"
    ["qwen0.5b"]="https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"
    # Llama Models
    ["llama70b"]="https://huggingface.co/meta-llama/Llama-2-70b-chat-hf-GGUF/resolve/main/llama-2-70b-chat.Q4_K_M.gguf"
    ["llama13b"]="https://huggingface.co/meta-llama/Llama-2-13b-chat-hf-GGUF/resolve/main/llama-2-13b-chat.Q5_K_M.gguf"
    ["llama7b_q5"]="https://huggingface.co/meta-llama/Llama-2-7b-chat-hf-GGUF/resolve/main/llama-2-7b-chat.Q5_K_M.gguf"
    ["llama7b_q2"]="https://huggingface.co/meta-llama/Llama-2-7b-chat-hf-GGUF/resolve/main/llama-2-7b-chat.Q2_K.gguf"
)

case $dl_choice in
    1)
        case "$GPU_LEVEL" in
            PREMIUM) MODEL_KEY="qwen72b"; MODEL_NAME="Qwen 2.5 72B" ;;
            HIGH) MODEL_KEY="qwen14b"; MODEL_NAME="Qwen 2.5 14B" ;;
            MID_HIGH) MODEL_KEY="qwen7b"; MODEL_NAME="Qwen 2.5 7B" ;;
            MID) MODEL_KEY="qwen3b"; MODEL_NAME="Qwen 2.5 3B" ;;
            LOW|UNSUPPORTED) MODEL_KEY="qwen1.5b"; MODEL_NAME="Qwen 2.5 1.5B" ;;
            *) MODEL_KEY="qwen7b"; MODEL_NAME="Qwen 2.5 7B" ;;
        esac

        echo -e "${Y}[*] Downloading ${MODEL_NAME}...${N}"
        wget --show-progress -O "$INSTALL_DIR/models/model.gguf" "${MODEL_URLS[$MODEL_KEY]}"
        check_error "Downloading model"
        ;;
    2)
        case "$GPU_LEVEL" in
            PREMIUM) MODEL_KEY="llama70b"; MODEL_NAME="Llama 2 70B" ;;
            HIGH) MODEL_KEY="llama13b"; MODEL_NAME="Llama 2 13B" ;;
            MID_HIGH) MODEL_KEY="llama7b_q5"; MODEL_NAME="Llama 2 7B Q5" ;;
            MID) MODEL_KEY="llama7b_q2"; MODEL_NAME="Llama 2 7B Q2" ;;
            LOW|UNSUPPORTED) MODEL_KEY="qwen0.5b"; MODEL_NAME="Qwen 2.5 0.5B" ;;
            *) MODEL_KEY="llama7b_q5"; MODEL_NAME="Llama 2 7B" ;;
        esac

        echo -e "${Y}[*] Downloading ${MODEL_NAME}...${N}"
        wget --show-progress -O "$INSTALL_DIR/models/model.gguf" "${MODEL_URLS[$MODEL_KEY]}"
        check_error "Downloading model"
        ;;
    3)
        read -p "Enter HuggingFace GGUF model URL: " custom_url
        read -p "Enter filename (without .gguf): " custom_name

        echo -e "${Y}[*] Downloading custom model...${N}"
        wget --show-progress -O "$INSTALL_DIR/models/${custom_name}.gguf" "$custom_url"
        check_error "Downloading custom model"
        ;;
    4)
        echo -e "${Y}[*] Skipping model download.${N}"
        echo -e "Download models manually to: ${C}$INSTALL_DIR/models${N}"
        ;;
esac

# ==============================================================================
# 8. POST-INSTALLATION SETUP & VERIFICATION
# ==============================================================================

echo -e "\n${C}════════════════════════════════════════════════════════${N}"
echo -e "${G}[✓] SETUP COMPLETE!${N}"
echo -e "${C}════════════════════════════════════════════════════════${N}\n"

echo -e "${Y}Quick Start Guide:${N}\n"

if [ -f "$INSTALL_DIR/models/model.gguf" ]; then
    MODEL_SIZE=$(ls -lh "$INSTALL_DIR/models/model.gguf" | awk '{print $5}')
    echo -e "✓ Model Ready: ${G}model.gguf${N} (${MODEL_SIZE})"
    echo -e "\n${Y}Run inference:${N}"
    echo -e "  ${C}bitnet -m $INSTALL_DIR/models/model.gguf -p \"Hello, how are you?\"${N}"
    echo -e "\n${Y}Run with server mode:${N}"
    echo -e "  ${C}bitnet --server -m $INSTALL_DIR/models/model.gguf${N}"
else
    echo -e "⚠ No model found. Add models to: ${C}$INSTALL_DIR/models${N}"
    echo -e "\n${Y}Then run:${N}"
    echo -e "  ${C}bitnet -m $INSTALL_DIR/models/YOUR_MODEL.gguf -p \"Your prompt here\"${N}"
fi

echo -e "\n${Y}Available Commands:${N}"
echo -e "  ${C}bitnet -h${N}                    # Show help"
echo -e "  ${C}bitnet -m MODEL.gguf -p \"Q\"${N}   # Chat inference"
echo -e "  ${C}bitnet -m MODEL.gguf --server${N} # Start API server"
echo -e "  ${C}bitnet -m MODEL.gguf -ngl 99${N}  # Force GPU acceleration"

echo -e "\n${Y}Configuration Summary:${N}"
echo -e "  SoC:             ${G}$SOC${N} ($CPU_VARIANT)"
echo -e "  GPU:             ${G}$GPU_TYPE${N} (${GPU_LEVEL})"
echo -e "  Threads:         ${G}$REC_THREADS${N}"
echo -e "  Batch Size:      ${G}$BATCH_SIZE${N}"
echo -e "  Context Length:  ${G}$CONTEXT_SIZE tokens${N}"
echo -e "  Effective RAM:   ${G}${EFFECTIVE_RAM} MB${N}"
echo -e "  Build Type:      ${Y}$BUILD_REC${N}"

echo -e "\n${Y}Performance Tips:${N}"
if [ "$GPU_SUPPORTED" = true ] && [ "$choice" != "3" ]; then
    echo -e "  💡 GPU acceleration available. Try ${C}-ngl 99${N} flag for speed boost"
fi
if [ "$EFFECTIVE_RAM" -lt 4000 ]; then
    echo -e "  💡 Low RAM detected. Use smaller models or reduce context with ${C}-n 256${N}"
fi

echo -e "\n${C}════════════════════════════════════════════════════════${N}"
echo -e "For support, visit: ${Y}$ISSUE_LINK${N}"
echo -e "${C}════════════════════════════════════════════════════════${N}\n"
~ $
