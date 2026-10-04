#!/bin/bash

export ARCH=arm64
mkdir -p out

TOPDIR=$(pwd)
CLANG_DIR=${TOPDIR}/toolchains/clang/clang-r416183b
GCC64_DIR=${TOPDIR}/toolchains/gcc64

# 1. 把 Clang 和 GCC 的 bin 目录同时加入 PATH
export PATH=${CLANG_DIR}/bin:${GCC64_DIR}/bin:$PATH

# 2. 正确指向 gcc64 里的交叉编译前缀 (aarch64-linux-android-)
BUILD_CROSS_COMPILE=${GCC64_DIR}/bin/aarch64-linux-android-

# 3. 指向 Clang 编译器
KERNEL_LLVM_BIN=${CLANG_DIR}/bin/clang
CLANG_TRIPLE=aarch64-linux-gnu-

KERNEL_MAKE_ENV="DTC_EXT=${TOPDIR}/tools/dtc CONFIG_BUILD_ARM64_DT_OVERLAY=y"

# 4. 生成配置文件
make -j1 -C ${TOPDIR} O=${TOPDIR}/out $KERNEL_MAKE_ENV ARCH=arm64 CROSS_COMPILE=$BUILD_CROSS_COMPILE REAL_CC=$KERNEL_LLVM_BIN CLANG_TRIPLE=$CLANG_TRIPLE CONFIG_SECTION_MISMATCH_WARN_ONLY=y vendor/p3q_chn_hkx_defconfig

# 5. 执行编译
make -j1 -C ${TOPDIR} O=${TOPDIR}/out $KERNEL_MAKE_ENV ARCH=arm64 CROSS_COMPILE=$BUILD_CROSS_COMPILE REAL_CC=$KERNEL_LLVM_BIN CLANG_TRIPLE=$CLANG_TRIPLE CONFIG_SECTION_MISMATCH_WARN_ONLY=y

# 6. 复制 Image 产物
cp out/arch/arm64/boot/Image ${TOPDIR}/arch/arm64/boot/Image
