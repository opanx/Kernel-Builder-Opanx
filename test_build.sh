#!/bin/bash
# Local test script to simulate GitHub Actions build
set -e

echo "=== Starting Local Kernel Build Test ==="

# Create working directory
WORKDIR="/workspace/build_test"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "Step 1: Installing dependencies..."
sudo apt-get update
sudo apt-get install -y build-essential bc gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi libssl-dev libfl-dev curl git zip unzip perl jq wget lsb-release software-properties-common gpg python3 python3-distutils clang lld llvm llvm-dev || true

echo "Step 2: Cloning kernel source..."
git clone --depth=1 -b android12-5.10 https://github.com/MillenniumOSS/android_kernel_common_android12-5.10.git kernel-source || {
    echo "Failed to clone kernel source"
    exit 1
}

cd kernel-source
echo "Kernel source cloned. Latest commit:"
git log -1 --oneline

echo "Step 3: Injecting ReSukiSU..."
curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s main || {
    echo "ReSukiSU injection failed, trying manual method..."
    git clone --depth=1 https://github.com/SukiSU-Ultra/SukiSU-Ultra.git temp_sukisu
    cp -rv temp_sukisu/KernelSU ./
    rm -rf temp_sukisu
}

echo "Step 4: Downloading SUSFS patch..."
cd "$WORKDIR"
git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android12-5.10 susfs-source || {
    echo "Failed to clone SUSFS gki branch, trying main..."
    git clone https://gitlab.com/simonpunk/susfs4ksu.git susfs-source
}

mkdir -p kernel-source/KernelSU/kernel
cp -v susfs-source/KernelSU/kernel/ksu_susfs.h kernel-source/KernelSU/kernel/ || echo "ksu_susfs.h copy skipped"
cp -rv susfs-source/kernel_patches/fs/* kernel-source/fs/ 2>/dev/null || echo "FS patches copy skipped"
cp -rv susfs-source/kernel_patches/include/linux/* kernel-source/include/linux/ 2>/dev/null || echo "Include patches copy skipped"

# Find and copy patch file
PATCH_FOUND=""
for patch in susfs-source/kernel_patches/*.patch; do
    if [ -f "$patch" ]; then
        cp -v "$patch" kernel-source/susfs.patch
        PATCH_FOUND="$patch"
        break
    fi
done

if [ -z "$PATCH_FOUND" ]; then
    echo "No patch file found!"
fi

cd kernel-source

# Get SUBLEVEL
SUBLEVEL=$(grep '^SUBLEVEL = ' Makefile | awk '{print $3}' || echo "0")
echo "Kernel SUBLEVEL: $SUBLEVEL"

# Apply fixes based on SUBLEVEL
if [ "$SUBLEVEL" -le "43" ] 2>/dev/null; then
    echo "Applying proc/base.c fix for SUBLEVEL <= 43"
    perl -i -pe 's/(int|size_t)\s+this_len\s*=\s*min_t\s*\(\s*\1\s*,/size_t this_len = min_t(size_t,/' fs/proc/base.c || echo "proc/base.c fix skipped"
fi

if [ "$SUBLEVEL" -le "117" ] 2>/dev/null; then
    echo "Applying fdinfo.c fixes for SUBLEVEL <= 117"
    sed -i '/^[[:space:]]*\/\*$/,/^[[:space:]]*u32 mask = mark->mask & IN_ALL_EVENTS;$/d' fs/notify/fdinfo.c 2>/dev/null || echo "fdinfo.c fix 1 skipped"
    perl -i -pe 's/\bmask,\s*mark->ignored_mask/inotify_mark_user_mask(mark)/g' fs/notify/fdinfo.c 2>/dev/null || echo "fdinfo.c fix 2 skipped"
    perl -i -pe 's/ignored_mask:%x/ignored_mask:0/g' fs/notify/fdinfo.c 2>/dev/null || echo "fdinfo.c fix 3 skipped"
fi

# Apply main SUSFS patch
echo "Applying SUSFS patch..."
if [ -f "susfs.patch" ]; then
    patch -p1 < susfs.patch || {
        echo "SUSFS patch failed, trying with --force..."
        patch -p1 --force < susfs.patch || echo "SUSFS patch application failed but continuing..."
    }
else
    echo "No susfs.patch found, skipping patch application"
fi

if [ "$SUBLEVEL" -le "209" ] 2>/dev/null; then
    echo "Applying task_mmu.c fix for SUBLEVEL <= 209"
    sed -i -e 's/goto show_pad;/return 0;/' ./fs/proc/task_mmu.c || echo "task_mmu.c fix skipped"
fi

echo "Step 5: Applying gaming optimizations..."
find . -name "Makefile" -o -name "Kbuild" | xargs sed -i 's/-O2/-O3/g' 2>/dev/null || true
find . -name "Makefile" -o -name "Kbuild" | xargs sed -i 's/-Werror//g' 2>/dev/null || true

cat >> arch/arm64/configs/gki_defconfig << 'EOF'

# Gaming optimizations
CONFIG_DEBUG_INFO_REDUCED=n
CONFIG_SLUB_DEBUG=n
CONFIG_PANIC_ON_OOPS=n
CONFIG_LOCKUP_DETECTOR=n
CONFIG_SCHED_DEBUG=n
CONFIG_PROFILING=y
CONFIG_PERF_EVENTS=y
CONFIG_HW_PERF_EVENTS=y
CONFIG_ARM_PMU=y
CONFIG_FRAME_WARN=4096
CONFIG_WERROR=n
CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y
CONFIG_CRYPTO_LZ4=y
CONFIG_CRYPTO_LZ4HC=y
CONFIG_ZRAM_DEF_COMP_LZ4=y
EOF

echo "Step 6: Configuring and compiling kernel..."
export PATH=/usr/lib/llvm-19/bin:/usr/lib/llvm-18/bin:/usr/lib/llvm-17/bin:$PATH
export CC=clang
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export STRIP=llvm-strip
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export LLVM=1
export LLVM_IAS=1

# Add SUSFS config
cat >> arch/arm64/configs/gki_defconfig << 'EOF'

# SUSFS Configuration
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=n
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_LOCALVERSION="-Panxcz-susfs"
EOF

echo "Configuring kernel..."
make O=out ARCH=arm64 gki_defconfig
make O=out ARCH=arm64 olddefconfig

echo "Starting kernel compilation with $(nproc --all) threads..."
make -j$(nproc --all) O=out ARCH=arm64 \
                      CC=clang \
                      LD=ld.lld \
                      AR=llvm-ar \
                      NM=llvm-nm \
                      OBJCOPY=llvm-objcopy \
                      OBJDUMP=llvm-objdump \
                      STRIP=llvm-strip \
                      CROSS_COMPILE=aarch64-linux-gnu- \
                      CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
                      LLVM=1 \
                      LLVM_IAS=1 2>&1 | tee build.log || {
    echo "Compilation failed! Check build.log for details"
    tail -200 build.log
    exit 1
}

echo "Kernel compilation completed!"
ls -lh out/arch/arm64/boot/

echo "Step 7: Creating flashable zip..."
cd "$WORKDIR"
git clone --depth=1 https://github.com/OSM0SIS/AnyKernel3.git AK3
if [ -f kernel-source/out/arch/arm64/boot/Image ]; then
    cp -v kernel-source/out/arch/arm64/boot/Image AK3/
elif [ -f kernel-source/out/arch/arm64/boot/Image.gz-dtb ]; then
    cp -v kernel-source/out/arch/arm64/boot/Image.gz-dtb AK3/Image
else
    echo "Error: Kernel image not found!"
    ls -la kernel-source/out/arch/arm64/boot/
    exit 1
fi

cd AK3
sed -i 's|block=/dev/block/platform/omap/omap_hsmmc.0/by-name/boot;|block=auto;|g' anykernel.sh
sed -i 's|is_slot_device=0;|is_slot_device=auto;|g' anykernel.sh
sed -i 's/do.devicecheck=1/do.devicecheck=0/g' anykernel.sh
zip -r9 ../Panxcz_kernel_susfs.zip *

echo "=== Build completed successfully! ==="
echo "Output file: $WORKDIR/Panxcz_kernel_susfs.zip"
