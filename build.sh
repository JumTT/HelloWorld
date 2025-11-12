#!/bin/bash

# =============================================================================
# Chromium 构建脚本
# 用于配置和构建 Chromium 项目
# =============================================================================

# 设置严格模式
set -euo pipefail

# 日志函数
log_info() {
    echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_warn() {
    echo "[WARN] $*" >&2
}

# 检查命令是否成功执行
check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "缺少必要命令: $1"
        exit 1
    fi
}

# 初始化构建配置
init_build_config() {
    log_info "初始化构建配置"
    
    if [ "${1:-}" = debug ]; then
        out=out/Debug
        flags="
    is_debug=true
    is_component_build=true"
        log_info "使用 Debug 配置"
    else
        out=out/Release
        flags="
    is_official_build=true
    exclude_unwind_tables=true
    enable_resource_allowlist_generation=false
    symbol_level=0"
        log_info "使用 Release 配置"
    fi
}

# 设置 sysroot
setup_sysroot() {
    log_info "导入 sysroot 配置脚本"
    . ./steup-sysroot.sh
}

# 配置编译缓存
configure_ccache() {
    log_info "配置编译缓存"
    CCACHE=""
    
    # 根据主机操作系统配置不同的缓存工具
    case "${host_os:-}" in
        linux|mac)
            if command -v ccache >/dev/null 2>&1; then
                export CCACHE_SLOPPINESS=time_macros
                export CCACHE_BASEDIR="$PWD"
                export CCACHE_CPP2=yes
                CCACHE=ccache
                log_info "使用 ccache 作为编译缓存"
            fi
            ;;
        win)
            if [ -f "$HOME"/.cargo/bin/sccache* ]; then
                export PATH="$PATH:$HOME/.cargo/bin"
                CCACHE=sccache
                log_info "使用 sccache 作为编译缓存"
            fi
            ;;
        *)
            log_warn "不支持的主机操作系统: ${host_os:-}"
            ;;
    esac
    
    # 如果有缓存工具，添加到构建参数
    if [ -n "$CCACHE" ]; then
        flags="$flags
    cc_wrapper=\"$CCACHE\""
    fi
}

# 设置基础构建参数
setup_base_flags() {
    log_info "设置基础构建参数"
    flags="$flags"'
  is_clang=true
  use_sysroot=false

  fatal_linker_warnings=false
  treat_warnings_as_errors=false

  enable_base_tracing=false
  use_udev=false
  use_aura=false
  use_ozone=false
  use_gio=false
  use_gtk=false
  use_platform_icu_alternatives=true
  use_glib=false

  disable_file_support=true
  enable_websockets=false
  use_kerberos=false
  enable_mdns=false
  enable_reporting=false
  include_transport_security_state_preload_list=false
  use_nss_certs=false

  enable_backup_ref_ptr_support=false
  enable_dangling_raw_ptr_checks=false
'
}

# 设置 sysroot 参数
setup_sysroot_flags() {
    if [ -n "${WITH_SYSROOT:-}" ]; then
        flags="$flags
    target_sysroot=\"//$WITH_SYSROOT\""
        log_info "设置 sysroot 参数: $WITH_SYSROOT"
    fi
}

# 设置 macOS 特定参数
setup_mac_flags() {
    if [ "${host_os:-}" = "mac" ]; then
        flags="$flags"'
    enable_dsyms=false'
        log_info "设置 macOS 特定参数"
    fi
}

# 设置 Android 特定参数
setup_android_flags() {
    case "$EXTRA_FLAGS" in
        *target_os=\"android\"*)
            flags="$flags"'
    is_high_end_android=true'
            log_info "设置 Android 特定参数"
            ;;
    esac
}

# 设置 MIPS 特定参数
# setup_mips_flags() {
#     if [ "${target_cpu:-}" = "mipsel" ] || [ "${target_cpu:-}" = "mips64el" ]; then
#         flags="$flags"'
#     use_thin_lto=false
#     chrome_pgo_phase=0'
#         log_info "设置 MIPS 特定参数"
#     fi
# }

# 设置 OpenWrt 静态构建参数
# setup_openwrt_flags() {
#     # OpenWrt static builds are bad with Clang 18+ and ThinLTO.
#     # Segfaults in fstack-protector on ARM.
#     case "$EXTRA_FLAGS" in
#         *build_static=true*)
#             flags="$flags"'
#     use_thin_lto=false'
#             log_info "设置 OpenWrt 静态构建参数"
#             ;;
#     esac
# }

# 准备输出目录
prepare_output_dir() {
    log_info "准备输出目录: $out"
    rm -rf "./$out"
    mkdir -p out
}

# 生成构建文件
generate_build_files() {
    log_info "生成构建文件"
    export DEPOT_TOOLS_WIN_TOOLCHAIN=0
    
    if ./gn/out/gn gen "$out" --args="$flags $EXTRA_FLAGS" --script-executable="${PYTHON:-python3}"; then
        log_info "构建文件生成成功"
    else
        log_error "构建文件生成失败"
        exit 1
    fi
}

# 执行构建
run_build() {
    log_info "开始构建"
    
    # 检查是否需要构建
    if echo "$EXTRA_FLAGS" | grep -vq 'build_static=true\|target_os="ios"'; then
        if command -v ninja >/dev/null 2>&1; then
            if ninja -C "$out" cronet; then
                log_info "构建成功完成"
            else
                log_error "构建失败"
                exit 1
            fi
        else
            log_error "未找到 ninja 构建工具"
            exit 1
        fi
    else
        log_info "根据配置跳过构建"
    fi
}

# 主执行流程
main() {
    log_info "开始 Chromium 构建流程"
    
    # 初始化构建配置
    init_build_config "$@"
    
    # 设置 sysroot
    setup_sysroot
    
    # 配置编译缓存
    configure_ccache
    
    # 设置构建参数
    setup_base_flags
    setup_sysroot_flags
    setup_mac_flags
    setup_android_flags
    # setup_mips_flags
    # setup_openwrt_flags
    
    # 准备输出目录
    prepare_output_dir
    
    # 生成构建文件
    generate_build_files
    
    # 执行构建
    run_build
    
    log_info "Chromium Cronet 构建流程完成"
}

# 执行主函数
main "$@"