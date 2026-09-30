#!/bin/bash

## DEVICE STUFF
DEVICE_HARDWARE="sm8350"
DEVICE_MODEL="$1"
ZIP_DIR="$(pwd)/AnyKernel3"
MOD_DIR="$ZIP_DIR/modules/vendor/lib/modules"
K_MOD_DIR="$(pwd)/out/modules"

# Enviorment Variables
SRC_DIR=$(pwd)
TC_DIR=$(pwd)/clang
JOBS="$(nproc --all)"
MAKE_PARAMS="-j$JOBS -C $SRC_DIR O=$SRC_DIR/out ARCH=arm64 CC=clang AS=clang LLVM=1 LLVM_IAS=1 CLANG_TRIPLE=$TC_DIR/bin/aarch64-linux-gnu- CROSS_COMPILE=$TC_DIR/bin/llvm-"
export PATH="$TC_DIR/bin:$PATH"

if [ "$DEVICE_MODEL" == "SM-G9980" ]; then
    DEVICE_NAME="p3q"
    DEFCONFIG=p3q_defconfig
else
    echo "Config not found"
    exit
fi

# Check if KSU flag is provided
if [[ "$*" == *"--ksu"* ]]; then
    KSU="true"
else
    KSU="false"
fi

# Check the value of KSU
if [ "$KSU" == "true" ]; then
    ZIP_NAME="Lavender_KSU_"$DEVICE_NAME"_"$DEVICE_MODEL"_"$(date +%d%m%y-%H%M)""
    SUFFIX="_KSU"
    if [ -d "KernelSU" ]; then
        echo "KernelSU exists"
    else
        echo "KernelSU not found !"
        echo "Fetching ...."
        curl -LSs "https://raw.githubusercontent.com/backslashxx/KernelSU/main/kernel/setup.sh" | bash -s master
    fi
elif [ "$KSU" == "false" ]; then
    echo "KSU disabled"
    ZIP_NAME="Lavender_"$DEVICE_NAME"_"$DEVICE_MODEL"_"$(date +%d%m%y-%H%M)""
    SUFFIX=""
    if [ -d "KernelSU" ]; then
        git reset HEAD --hard
    fi
fi

make $MAKE_PARAMS $DEFCONFIG
make $MAKE_PARAMS
make $MAKE_PARAMS INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install

if [ -d "AnyKernel3" ]; then
    cd AnyKernel3
    git reset HEAD --hard
    cd ..
    if [ -d "AnyKernel3/modules" ]; then
        rm -rf AnyKernel3/modules/
        mkdir AnyKernel3/modules/
        mkdir AnyKernel3/modules/vendor/
        mkdir AnyKernel3/modules/vendor/lib
        mkdir AnyKernel3/modules/vendor/lib/modules/
    else
        mkdir AnyKernel3/modules/
        mkdir AnyKernel3/modules/vendor/
        mkdir AnyKernel3/modules/vendor/lib
        mkdir AnyKernel3/modules/vendor/lib/modules/
    fi
    find "$(pwd)/out/modules" -type f -iname "*.ko" -exec cp -r {} ./AnyKernel3/modules/vendor/lib/modules/ \;
    cp ./out/arch/arm64/boot/Image ./AnyKernel3/
    cp ./out/arch/arm64/boot/dtbo.img ./AnyKernel3/
    cd AnyKernel3
    rm -rf Lavender*
    zip -r9 $ZIP_NAME . -x '*.git*' '*patch*' '*ramdisk*' 'LICENSE' 'README.md'
    cd ..
else
    git clone https://github.com/yanzihan/AnyKernel3 -b samsung
    if [ -d "AnyKernel3/modules" ]; then
        rm -rf AnyKernel3/modules/
        mkdir AnyKernel3/modules/
        mkdir AnyKernel3/modules/vendor/
        mkdir AnyKernel3/modules/vendor/lib
        mkdir AnyKernel3/modules/vendor/lib/modules/
    else
        mkdir AnyKernel3/modules/
        mkdir AnyKernel3/modules/vendor/
        mkdir AnyKernel3/modules/vendor/lib
        mkdir AnyKernel3/modules/vendor/lib/modules/
    fi
    find "$(pwd)/out/modules" -type f -iname "*.ko" -exec cp -r {} ./AnyKernel3/modules/vendor/lib/modules/ \;
    cp ./out/arch/arm64/boot/Image ./AnyKernel3/
    cp ./out/arch/arm64/boot/dtbo.img ./AnyKernel3/
    cd AnyKernel3
    rm -rf Lavender*
    zip -r9 $ZIP_NAME . -x '*.git*' '*patch*' '*ramdisk*' 'LICENSE' 'README.md'
    cd ..
fi

IMAGE_SRC="./out/arch/arm64/boot/Image"
DTB_SRC="./out/arch/arm64/boot/dts/vendor/qcom/dtb"
DTBO_SRC="./out/arch/arm64/boot/dtbo.img"
RAMDISK_SRC="./boot/ramdisk"
OUT_BOOT_NAME="boot.img"
OUT_DTBO_NAME="dtbo.img"
    CMDLINE="console=null androidboot.hardware=qcom androidboot.memcg=1 lpm_levels.sleep_disabled=1 video=vfb:640x400,bpp=32,memsize=3072000 msm_rtb.filter=0x237 service_locator.enable=1 androidboot.usbcontroller=a600000.dwc3 swiotlb=2048 loop.max_part=7 cgroup.memory=nokmem,nosocket firmware_class.path=/vendor/firmware_mnt/image printk.devkmsg=on pcie_ports=compat cpuinfo.chipname=SM8350 panic=4"
BOARD="SRPTI01C016"
MONTH="$(date +%Y-%m)"

if [ -f "$DTBO_SRC" ]; then
    cp "$DTBO_SRC" "./$OUT_DTBO_NAME"
    echo "dtbo.img Successfully exported: $OUT_DTBO_NAME"
fi

if [ -f "$IMAGE_SRC" ]; then
    echo "Packing now $OUT_BOOT_NAME ..."
    MKBOOTIMG_ARGS=(
        --kernel "$IMAGE_SRC"
        --header_version 3
        --cmdline "$CMDLINE"
        --board "$BOARD"
        --os_version 16.0.0
        --os_patch_level "$MONTH"
    )
    if [ -f "$DTB_SRC" ]; then
        MKBOOTIMG_ARGS+=(--dtb "$DTB_SRC")
        echo "Found dtb: $DTB_SRC"
    fi
    if [ -f "$RAMDISK_SRC" ]; then
        MKBOOTIMG_ARGS+=(--ramdisk "$RAMDISK_SRC")
        echo "Found ramdisk: $RAMDISK_SRC"
    else
        echo "WARNING: ramdisk not found at $RAMDISK_SRC, building boot.img WITHOUT ramdisk!"
    fi

    MKBOOTIMG_ARGS+=(-o "$OUT_BOOT_NAME")
    mkbootimg "${MKBOOTIMG_ARGS[@]}"
    echo "boot.img Successfully generated: $OUT_BOOT_NAME"
fi
