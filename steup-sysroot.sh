#!/bin/bash

# =============================================================================
# 平台检测和配置脚本
# 检测主机操作系统和CPU架构，并设置相应的构建参数
# =============================================================================

eval "$EXTRA_FLAGS"

# 设置严格模式
set -euo pipefail

# 日志函数
log_info() {
    echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

# 检测主机操作系统
detect_host_os() {
    case "$(uname)" in
        MINGW*|MSYS*)
            host_os=win
            log_info "检测到 Windows 主机操作系统"
            ;;
        Linux)
            host_os=linux
            log_info "检测到 Linux 主机操作系统"
            ;;
        Darwin)
            host_os=mac
            log_info "检测到 macOS 主机操作系统"
            ;;
        *)
            log_error "不支持的主机操作系统: $(uname)"
            exit 1
            ;;
    esac
}

# 检测主机CPU架构
detect_host_cpu() {
    case "$(uname -m)" in
        x86_64|x64)
            host_cpu=x64
            log_info "检测到 x64 CPU 架构"
            ;;
        x86|i386|i686)
            host_cpu=x86
            log_info "检测到 x86 CPU 架构"
            ;;
        arm)
            host_cpu=arm
            log_info "检测到 ARM CPU 架构"
            ;;
        arm64|aarch64|armv8b|armv8l)
            host_cpu=arm64
            log_info "检测到 ARM64 CPU 架构"
            ;;
        *)
            log_error "不支持的主机 CPU 架构: $(uname -m)"
            exit 1
            ;;
    esac
}

# 初始化变量
detect_host_os
detect_host_cpu

# 设置目标平台（默认与主机相同）
if [ -z "${target_os:-}" ]; then
    target_os="$host_os"
    log_info "未指定目标操作系统，使用主机操作系统: $target_os"
else
    log_info "使用指定的目标操作系统: $target_os"
fi

if [ -z "${target_cpu:-}" ]; then
    target_cpu="$host_cpu"
    log_info "未指定目标 CPU 架构，使用主机 CPU 架构: $target_cpu"
else
    log_info "使用指定的目标 CPU 架构: $target_cpu"
fi

# 查找 Python 解释器
PYTHON=$(which python3 2>/dev/null || which python 2>/dev/null || true)
if [ -z "$PYTHON" ]; then
    log_error "未找到 Python 解释器"
    exit 1
fi
log_info "找到 Python 解释器: $PYTHON"

# sysroot 配置
configure_sysroot() {
    case "$target_os" in
        linux)
            # 根据目标CPU架构设置sysroot架构
            case "$target_cpu" in
                x64)     SYSROOT_ARCH=amd64;;
                x86)     SYSROOT_ARCH=i386;;
                arm64)   SYSROOT_ARCH=arm64;;
                arm)     SYSROOT_ARCH=armhf;;
                mipsel)  SYSROOT_ARCH=mipsel;;
                mips64el) SYSROOT_ARCH=mips64el;;
                riscv64) SYSROOT_ARCH=riscv64;;
                *)
                    log_error "Linux 平台不支持的目标 CPU 架构: $target_cpu"
                    exit 1
                    ;;
            esac
            
            # 设置sysroot路径
            if [ -n "${SYSROOT_ARCH:-}" ]; then
                WITH_SYSROOT="out/sysroot-build/bullseye/bullseye_${SYSROOT_ARCH}_staging"
                log_info "设置 Linux sysroot: $WITH_SYSROOT"
            fi
            ;;
            
        openwrt)
            # OpenWRT 配置
            if [ -n "${OPENWRT_FLAGS:-}" ]; then
                eval "$OPENWRT_FLAGS"
                WITH_SYSROOT="out/sysroot-build/openwrt/$release/$arch"
                log_info "设置 OpenWRT sysroot: $WITH_SYSROOT"
            else
                log_error "OPENWRT_FLAGS 未定义"
                exit 1
            fi
            ;;
            
        android)
            # Android 配置
            WITH_SYSROOT=
            case "$target_cpu" in
                x64)     WITH_ANDROID_IMG=x86_64-24_r08;;
                x86)     WITH_ANDROID_IMG=x86-24_r08;;
                arm64)   WITH_ANDROID_IMG=arm64-v8a-24_r07;;
                arm)     WITH_ANDROID_IMG=armeabi-v7a-24_r07;;
                *)
                    log_error "Android 平台不支持的目标 CPU 架构: $target_cpu"
                    exit 1
                    ;;
            esac
            log_info "设置 Android 镜像: $WITH_ANDROID_IMG"
            ;;
            
        *)
            log_info "目标操作系统 $target_os 不需要特殊 sysroot 配置"
            ;;
    esac
}

# 执行sysroot配置
configure_sysroot

# 输出配置结果
log_info "平台配置完成:"
log_info "  主机操作系统: $host_os"
log_info "  主机CPU架构: $host_cpu"
log_info "  目标操作系统: $target_os"
log_info "  目标CPU架构: $target_cpu"