#!/bin/bash

# =============================================================================
# Android 系统镜像设置脚本
# 用于下载和设置 Android 系统镜像用于构建
# =============================================================================

# 设置严格模式
set -euo pipefail

# 导入平台配置脚本
echo "[INFO] 导入平台配置脚本..." >&2
. ./steup-sysroot.sh

# 日志函数
log_info() {
    echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

# 检查命令是否成功执行
check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "缺少必要命令: $1"
        exit 1
    fi
}

# 确保必要命令存在
check_command aria2c
check_command unzip
check_command sudo

# 设置 Android 系统镜像
setup_android_img() {
    # 检查是否需要设置 Android 镜像
    if [ -n "${WITH_ANDROID_IMG:-}" ] && [ ! -d "out/sysroot-build/android/$WITH_ANDROID_IMG/system" ]; then
        log_info "设置 Android 系统镜像: $WITH_ANDROID_IMG"
        
        # 创建必要的目录
        mkdir -p out/sysroot-build/android/"$WITH_ANDROID_IMG"
        
        # 下载 Android 系统镜像
        img_url="https://dl.google.com/android/repository/sys-img/android/$WITH_ANDROID_IMG.zip"
        log_info "下载 Android 系统镜像: $img_url"
        
        if aria2c -x 16 -s 16 --continue=true "$img_url"; then
            log_info "Android 系统镜像下载成功"
        else
            log_error "Android 系统镜像下载失败: $img_url"
            exit 1
        fi
        
        # 创建挂载点
        mkdir -p "$WITH_ANDROID_IMG/mount"
        
        # 解压系统镜像
        if unzip "$WITH_ANDROID_IMG.zip" '*/system.img' -d "$WITH_ANDROID_IMG"; then
            log_info "Android 系统镜像解压成功"
        else
            log_error "Android 系统镜像解压失败"
            exit 1
        fi
        
        # 挂载系统镜像
        if sudo mount "$WITH_ANDROID_IMG"/*/system.img "$WITH_ANDROID_IMG/mount"; then
            log_info "Android 系统镜像挂载成功"
        else
            log_error "Android 系统镜像挂载失败"
            exit 1
        fi
        
        # 设置目标文件系统路径
        rootfs="out/sysroot-build/android/$WITH_ANDROID_IMG"
        mkdir -p "$rootfs/system/bin" "$rootfs/system/etc"
        
        # 复制必要的文件
        if cp "$WITH_ANDROID_IMG/mount/bin/linker"* "$rootfs/system/bin" && \
           cp "$WITH_ANDROID_IMG/mount/etc/hosts" "$rootfs/system/etc" && \
           cp -r "$WITH_ANDROID_IMG/mount/lib"* "$rootfs/system"; then
            log_info "文件复制成功"
        else
            log_error "文件复制失败"
            # 尝试卸载并清理
            sudo umount "$WITH_ANDROID_IMG/mount" 2>/dev/null || true
            rm -rf "$WITH_ANDROID_IMG" "$WITH_ANDROID_IMG.zip"
            exit 1
        fi
        
        # 卸载系统镜像
        if sudo umount "$WITH_ANDROID_IMG/mount"; then
            log_info "Android 系统镜像卸载成功"
        else
            log_warn "Android 系统镜像卸载失败"
        fi
        
        # 清理临时文件
        rm -rf "$WITH_ANDROID_IMG" "$WITH_ANDROID_IMG.zip"
        log_info "Android 系统镜像设置完成"
    else
        log_info "Android 系统镜像已存在或不需要设置"
    fi
}

setup_android_img