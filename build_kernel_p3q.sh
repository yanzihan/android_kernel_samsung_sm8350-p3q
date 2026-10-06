#!/bin/bash
# ============================================================
# p3q (Galaxy S21 chn_hkx) 内核一键构建脚本
# 产物: dist/boot.img + dist/dtbo.img + dist/Image
#
# 依赖:
#   toolchains/clang + toolchains/gcc64        编译工具链
#   tools/mkdtimg                              树内自带, 生成 dtbo.img
#   magiskboot                                 打包 boot.img (PATH 或 tools/ 下)
#   boot/base.img                              UN1CA 原版 boot.img (底包)
#
# boot/ 目录约定:
#   boot/base.img      必需 - UN1CA 原版 boot.img, 继承其 boot 头格式/页大小
#   boot/ramdisk.cpio  可选 - 放这里则替换底包 ramdisk (newc 格式)
#   boot/ramdisk/      可选 - 或放一个目录, 脚本自动打包成 cpio
#   两者都不放则沿用底包 ramdisk
# ============================================================

export ARCH=arm64

TOPDIR=$(pwd)
CLANG_DIR=${TOPDIR}/toolchains/clang/clang-r416183b
GCC64_DIR=${TOPDIR}/toolchains/gcc64
DIST=${TOPDIR}/dist                # 最终产物输出目录
BOOT_DIR=${TOPDIR}/boot            # base.img / ramdisk 存放处
WORK_DIR=${BOOT_DIR}/work          # magiskboot 临时工作目录

BOOT_PARTITION_SIZE=100663296      # 96 MiB
DTBO_PARTITION_SIZE=25165824       # 24 MiB

export PATH=${CLANG_DIR}/bin:${GCC64_DIR}/bin:$PATH

BUILD_CROSS_COMPILE=${GCC64_DIR}/bin/aarch64-linux-android-
KERNEL_LLVM_BIN=${CLANG_DIR}/bin/clang
CLANG_TRIPLE=aarch64-linux-gnu-

KERNEL_MAKE_ENV="DTC_EXT=${TOPDIR}/tools/dtc CONFIG_BUILD_ARM64_DT_OVERLAY=y"
MAKE_ARGS="-j16 -C ${TOPDIR} O=${TOPDIR}/out ${KERNEL_MAKE_ENV} ARCH=arm64 CROSS_COMPILE=${BUILD_CROSS_COMPILE} REAL_CC=${KERNEL_LLVM_BIN} CLANG_TRIPLE=${CLANG_TRIPLE} CONFIG_SECTION_MISMATCH_WARN_ONLY=y"

# p3q 的 5 个硬件版本 dtbo (顺序与 dts Makefile 中 dtbo-y 一致)
P3Q_DTBO_REV=(r11 r09 r07 r05 r03)
DTBO_DTS_DIR=arch/arm64/boot/dts/samsung/palette/p3q

check_size() {
    local name=$1 file=$2 limit=$3
    local sz
    sz=$(stat -c%s "$file")
    if [ "$sz" -le "$limit" ]; then
        printf "✅ %-10s %10d / %d bytes (剩余 %d)\n" "$name" "$sz" "$limit" "$((limit - sz))"
    else
        printf "❌ %-10s %10d bytes 超出分区大小 %d!\n" "$name" "$sz" "$limit"
        exit 1
    fi
}

echo "=== 0. 检查依赖 ==="
MAGISKBOOT=$(command -v magiskboot 2>/dev/null)
[ -z "$MAGISKBOOT" ] && [ -x "${TOPDIR}/tools/magiskboot" ] && MAGISKBOOT="${TOPDIR}/tools/magiskboot"
if [ -z "$MAGISKBOOT" ]; then
    echo "❌ 找不到 magiskboot (PATH 或 ${TOPDIR}/tools/)"
    echo "   可从 Magisk 发布包中提取: https://github.com/topjohnwu/Magisk/releases"
    exit 1
fi
if [ ! -x "${TOPDIR}/tools/mkdtimg" ]; then
    echo "❌ 找不到 ${TOPDIR}/tools/mkdtimg"
    exit 1
fi
if [ ! -f "${BOOT_DIR}/base.img" ]; then
    echo "❌ 缺少 ${BOOT_DIR}/base.img (请放入 UN1CA 原版 boot.img)"
    exit 1
fi
echo "✅ 依赖齐全 (magiskboot: ${MAGISKBOOT})"

echo "=== 1. 开始生成配置 ==="
rm -rf out
mkdir -p out
make ${MAKE_ARGS} vendor/p3q_chn_hkx_defconfig
if [ $? -ne 0 ]; then
    echo "❌ 配置生成失败！"
    exit 1
fi

echo "=== 2. 开始多线程编译 ==="
make ${MAKE_ARGS} 2>&1 | tee build.log
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "❌ 编译报错！请检查上方终端输出，或直接查看生成的 build.log 文件。"
    exit 1
fi

echo "=== 3. 构建 5 个硬件版本 dtbo ==="
DTBO_FILES=""
for rev in "${P3Q_DTBO_REV[@]}"; do
    target="${DTBO_DTS_DIR}/p3q_chn_hkx_w00_${rev}.dtbo"
    make ${MAKE_ARGS} "$target"
    if [ $? -ne 0 ]; then
        echo "❌ dtbo 构建失败: $target"
        exit 1
    fi
    DTBO_FILES+=" out/$target"
done

echo "=== 4. 生成 dtbo.img ==="
mkdir -p "$DIST"
rm -f ${DIST}/dtbo.img
${TOPDIR}/tools/mkdtimg create ${DIST}/dtbo.img --page_size=4096 ${DTBO_FILES}
if [ $? -ne 0 ]; then
    echo "❌ dtbo.img 生成失败！"
    exit 1
fi

echo "=== 5. 打包 boot.img ==="
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cp ${BOOT_DIR}/base.img ${WORK_DIR}/boot.img
(cd "$WORK_DIR" && ${MAGISKBOOT} unpack boot.img)
if [ $? -ne 0 ]; then
    echo "❌ 解包底包 boot.img 失败！"
    exit 1
fi

# 替换内核; repack 时 magiskboot 会按底包原有的压缩格式重新压缩
cp out/arch/arm64/boot/Image ${WORK_DIR}/kernel
if [ $? -ne 0 ]; then
    echo "❌ 拷贝 Image 失败！"
    exit 1
fi

# 替换 ramdisk (可选: boot/ramdisk.cpio 或 boot/ramdisk/ 目录)
if [ -f "${BOOT_DIR}/ramdisk.cpio" ]; then
    cp ${BOOT_DIR}/ramdisk.cpio ${WORK_DIR}/ramdisk.cpio
    echo "   使用自定义 ramdisk: boot/ramdisk.cpio"
elif [ -d "${BOOT_DIR}/ramdisk" ]; then
    (cd ${BOOT_DIR}/ramdisk && find . | cpio -o -H newc --quiet > ${WORK_DIR}/ramdisk.cpio)
    if [ $? -ne 0 ]; then
        echo "❌ 打包 boot/ramdisk/ 目录失败！"
        exit 1
    fi
    echo "   使用自定义 ramdisk: boot/ramdisk/ 目录"
else
    echo "   未提供自定义 ramdisk, 沿用底包 ramdisk"
fi

(cd "$WORK_DIR" && ${MAGISKBOOT} repack boot.img ${DIST}/boot.img)
if [ $? -ne 0 ]; then
    echo "❌ 打包 boot.img 失败！"
    exit 1
fi
rm -rf "$WORK_DIR"

echo "=== 6. 汇总产物 ==="
cp out/arch/arm64/boot/Image ${DIST}/Image
cp out/arch/arm64/boot/Image ${TOPDIR}/arch/arm64/boot/Image

echo "=== 7. 分区容量校验 ==="
check_size "boot.img"  ${DIST}/boot.img  ${BOOT_PARTITION_SIZE}
check_size "dtbo.img"  ${DIST}/dtbo.img  ${DTBO_PARTITION_SIZE}

echo "=== 8. 组装 AnyKernel3 卡刷包 + Magisk 模块 ==="
STAMP=$(date +%Y%m%d-%H%M)
AK3=${TOPDIR}/AnyKernel3
if [ -d "$AK3" ] && [ -f "$AK3/anykernel.sh" ]; then
    # 清理旧产物与占位文件, 放入新内核与模块
    rm -f ${AK3}/Image ${AK3}/Image.gz ${AK3}/Image.gz-dtb ${AK3}/dtbo
    rm -rf ${AK3}/modules/system/vendor/lib/modules
    mkdir -p ${AK3}/modules/system/vendor/lib/modules
    cp out/arch/arm64/boot/Image ${AK3}/Image
    find out -name '*.ko' -not -path '*tmp*' -exec cp {} ${AK3}/modules/system/vendor/lib/modules/ \;
    (cd ${AK3} && zip -r9 ${DIST}/AK3-p3q-${STAMP}.zip . -x '.git/*' > /dev/null)
    echo "   ✅ AK3 卡刷包: dist/AK3-p3q-${STAMP}.zip (TWRP/ recovery 刷入)"
else
    echo "   ⚠ 未找到 AnyKernel3/, 跳过卡刷包"
fi

# Magisk 模块 (无需 recovery, 有 root 即可安装模块部分)
MK=${TOPDIR}/.mkmodule_build
rm -rf ${MK}
mkdir -p ${MK}/system/vendor/lib/modules
cat > ${MK}/module.prop <<EOF
id=p3q_kernel_modules
name=P3Q Kernel Modules
version=${STAMP}
versionCode=$(date +%Y%m%d)
author=yanzihan
description=Kernel modules (touch/audio/camera/bt/nfc/fp) for p3q custom kernel
EOF
find out -name '*.ko' -not -path '*tmp*' -exec cp {} ${MK}/system/vendor/lib/modules/ \;
(cd ${MK} && zip -r9 ${DIST}/p3q-modules-${STAMP}.zip . > /dev/null)
rm -rf ${MK}
echo "   ✅ Magisk 模块: dist/p3q-modules-${STAMP}.zip (magisk --install-module 安装)"

echo ""
ls -la ${DIST}
echo "✅ 全部完成！产物目录: ${DIST}/  (boot.img dtbo.img Image)"
