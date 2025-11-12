#!/bin/bash

# =============================================================================
# Depot 工具和依赖项设置脚本
# 用于下载和设置 Chromium 构建所需的各种工具和依赖项
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

# 确保必要命令存在
check_command aria2c
check_command grep
check_command cut

# 构建 sysroot（如果需要）
setup_sysroot() {
    if [ -n "${SYSROOT_ARCH:-}" ] && [ ! -d "./$WITH_SYSROOT/lib" ]; then
        log_info "构建 sysroot: $SYSROOT_ARCH"
        if [ -f "./build/linux/sysroot_scripts/sysroot-creator.sh" ]; then
            ./build/linux/sysroot_scripts/sysroot-creator.sh build "$SYSROOT_ARCH"
        else
            log_warn "sysroot 脚本不存在: ./build/linux/sysroot_scripts/sysroot-creator.sh"
        fi
    fi
}

# 设置 OpenWRT（如果需要）
# setup_openwrt() {
#     if [ -n "${OPENWRT_FLAGS:-}" ]; then
#         log_info "设置 OpenWRT"
#         if [ -f "./get-openwrt.sh" ]; then
#             ./get-openwrt.sh
#         else
#             log_warn "OpenWRT 脚本不存在: ./get-openwrt.sh"
#         fi
#     fi
# }

# 设置 Clang 编译器
setup_clang() {
    log_info "设置 Clang 编译器"
    
    # 根据主机平台设置 Clang 配置
    case "$host_os" in
        linux) WITH_CLANG=Linux_x64;;
        win) WITH_CLANG=Win;;
        mac) WITH_CLANG=Mac;;
        *) 
            log_error "不支持的主机操作系统用于 Clang: $host_os"
            exit 1
            ;;
    esac
    
    # macOS ARM64 特殊处理
    if [ "$host_os" = mac ] && [ "$host_cpu" = arm64 ]; then
        WITH_CLANG=Mac_arm64
    fi
    
    # 创建目标目录
    mkdir -p third_party/llvm-build/Release+Asserts
    
    # 获取 Clang 版本
    if [ -f "tools/clang/scripts/update.py" ]; then
        cd tools/clang/scripts
        CLANG_REVISION=$($PYTHON -c 'import update; print(update.PACKAGE_VERSION)' 2>/dev/null || echo "")
        cd -
        
        if [ -n "$CLANG_REVISION" ]; then
            echo "$CLANG_REVISION" > third_party/llvm-build/Release+Asserts/cr_build_revision
            
            # 下载并解压 Clang（如果尚未存在）
            if [ ! -d third_party/llvm-build/Release+Asserts/bin ]; then
                log_info "下载 Clang 版本: $CLANG_REVISION"
                mkdir -p third_party/llvm-build/Release+Asserts
                clang_path="clang-$CLANG_REVISION.tgz"
                clang_url="https://commondatastorage.googleapis.com/chromium-browser-clang/$WITH_CLANG/$clang_path"
                
                if aria2c -x 16 -s 16 --continue=true "$clang_url" | tar xzf - -C third_party/llvm-build/Release+Asserts; then
                    log_info "Clang 下载并解压成功"
                else
                    log_error "Clang 下载失败: $clang_url"
                    exit 1
                fi
            else
                log_info "Clang 已存在，跳过下载"
            fi
        else
            log_error "无法获取 Clang 版本信息"
            exit 1
        fi
    else
        log_warn "Clang 更新脚本不存在: tools/clang/scripts/update.py"
    fi
}

# 设置 sccache（仅限 Windows）
setup_sccache() {
    if [ "$host_os" = win ] && [ ! -f ~/.cargo/bin/sccache.exe ]; then
        log_info "设置 sccache"
        sccache_url="https://github.com/mozilla/sccache/releases/download/0.2.12/sccache-0.2.12-x86_64-pc-windows-msvc.tar.gz"
        mkdir -p ~/.cargo/bin
        
        if aria2c -x 16 -s 16 --continue=true "$sccache_url" | tar xzf - --strip=1 -C ~/.cargo/bin; then
            log_info "sccache 安装成功"
        else
            log_error "sccache 下载失败: $sccache_url"
            exit 1
        fi
    fi
}

# 设置 GN 构建工具
setup_gn() {
    log_info "设置 GN 构建工具"
    
    # 根据主机平台设置 GN 配置
    case "$host_os" in
        linux) WITH_GN=linux-amd64;;
        win) WITH_GN=windows-amd64;;
        mac) WITH_GN=mac-amd64;;
        *) 
            log_error "不支持的主机操作系统用于 GN: $host_os"
            exit 1
            ;;
    esac
    
    # macOS ARM64 特殊处理
    if [ "$host_os" = mac ] && [ "$host_cpu" = arm64 ]; then
        WITH_GN=mac-arm64
    fi
    
    # 下载 GN（如果尚未存在）
    if [ ! -f gn/out/gn ]; then
        if [ -f "DEPS" ]; then
            gn_version=$(grep "'gn_version':" DEPS | cut -d"'" -f4)
            if [ -n "$gn_version" ]; then
                log_info "下载 GN 版本: $gn_version"
                mkdir -p gn/out
                
                if aria2c -x 16 -s 16 --continue=true --out=gn.zip "https://chrome-infra-packages.appspot.com/dl/gn/gn/$WITH_GN/+/$gn_version"; then
                    if unzip -q gn.zip -d gn/out; then
                        rm -f gn.zip
                        log_info "GN 下载并解压成功"
                    else
                        log_error "GN 解压失败"
                        exit 1
                    fi
                else
                    log_error "GN 下载失败"
                    exit 1
                fi
            else
                log_error "无法从 DEPS 文件获取 GN 版本"
                exit 1
            fi
        else
            log_warn "DEPS 文件不存在"
        fi
    else
        log_info "GN 已存在，跳过下载"
    fi
}

# 设置 PGO (Profile-Guided Optimization) 配置文件
setup_pgo() {
    log_info "设置 PGO 配置文件"
    
    # 根据目标平台设置 PGO 配置
    case "$target_os" in
        win)
            case "$target_cpu" in
                arm64) WITH_PGO=win-arm64;;
                x64) WITH_PGO=win64;;
                *) WITH_PGO=win32;;
            esac
            ;;
        mac)
            case "$target_cpu" in
                arm64) WITH_PGO=mac-arm;;
                *) WITH_PGO=mac;;
            esac
            ;;
        linux|openwrt)
            WITH_PGO=linux
            ;;
        android)
            case "$target_cpu" in
                arm64) WITH_PGO=android-arm64;;
                *) WITH_PGO=android-arm32;;
            esac
            ;;
        *)
            log_info "目标平台 $target_os 不需要 PGO 配置"
            return 0
            ;;
    esac
    
    # 获取 PGO 路径
    if [ -n "${WITH_PGO:-}" ] && [ -f "chrome/build/$WITH_PGO.pgo.txt" ]; then
        PGO_PATH=$(cat "chrome/build/$WITH_PGO.pgo.txt")
        
        # 下载 PGO 配置文件（如果尚未存在）
        if [ -n "$PGO_PATH" ] && [ ! -f "chrome/build/pgo_profiles/$PGO_PATH" ]; then
            log_info "下载 PGO 配置文件: $PGO_PATH"
            mkdir -p chrome/build/pgo_profiles
            
            if aria2c -x 16 -s 16 --continue=true "https://storage.googleapis.com/chromium-optimization-profiles/pgo_profiles/$PGO_PATH"; then
                log_info "PGO 配置文件下载成功"
            else
                log_error "PGO 配置文件下载失败: $PGO_PATH"
                exit 1
            fi
        else
            log_info "PGO 配置文件已存在或不需要，跳过下载"
        fi
    else
        log_info "PGO 配置文件不存在或不需要"
    fi
}

# 设置 Android NDK（如果需要）
setup_android_ndk() {
    if [ "$target_os" = android ] && [ ! -d third_party/android_toolchain/ndk ]; then
        log_info "设置 Android NDK"
        
        # 获取 Android NDK 版本
        if [ -f "build/config/android/config.gni" ]; then
            android_ndk_version=$(grep 'default_android_ndk_version = ' build/config/android/config.gni | cut -d'"' -f2)
            
            if [ -n "$android_ndk_version" ]; then
                log_info "下载 Android NDK 版本: $android_ndk_version"
                
                # 下载 Android NDK
                if aria2c -x 16 -s 16 --continue=true "https://dl.google.com/android/repository/android-ndk-$android_ndk_version-linux.zip"; then
                    if unzip -q "android-ndk-$android_ndk_version-linux.zip"; then
                        mkdir -p third_party/android_toolchain/ndk
                        
                        # 复制必要的文件
                        cd "android-ndk-$android_ndk_version"
                        cp -r --parents sources/android/cpufeatures ../third_party/android_toolchain/ndk
                        cp -r --parents toolchains/llvm/prebuilt ../third_party/android_toolchain/ndk
                        cd ..
                        
                        # 清理不需要的文件
                        cd third_party/android_toolchain/ndk
                        find toolchains -type f -regextype egrep \! -regex \
                            '.*(lib(atomic|gcc|gcc_real|compiler_rt-extras|android_support|unwind).a|crt.*o|lib(android|c|dl|log|m).so|usr/local.*|usr/include.*)' -delete
                        cd -
                        
                        # 清理临时文件
                        rm -rf "android-ndk-$android_ndk_version" "android-ndk-$android_ndk_version-linux.zip"
                        log_info "Android NDK 设置成功"
                    else
                        log_error "Android NDK 解压失败"
                        exit 1
                    fi
                else
                    log_error "Android NDK 下载失败"
                    exit 1
                fi
            else
                log_error "无法获取 Android NDK 版本"
                exit 1
            fi
        else
            log_warn "Android 配置文件不存在: build/config/android/config.gni"
        fi
    fi
}

# 主执行流程
main() {
    log_info "开始设置 Depot 工具和依赖项"
    
    # 执行各个设置步骤
    setup_sysroot
    # setup_openwrt
    setup_clang
    setup_sccache
    setup_gn
    setup_pgo
    setup_android_ndk
    
    log_info "Depot 工具和依赖项设置完成"
}

# 执行主函数
main "$@"