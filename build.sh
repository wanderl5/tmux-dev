#!/usr/bin/env bash
# =============================================================================
# tmux 一键编译脚本
# 用法：./build.sh [选项]
#   -c, --clean     编译前清理产物（make clean）
#   -i, --install   编译后安装到 ~/.local/bin
#   -j N            并发数（默认：nproc 自动检测）
#   -h, --help      显示帮助
# =============================================================================
set -euo pipefail

# ---------- 颜色输出 ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

# ---------- 默认参数 ----------
CLEAN=0
INSTALL=0
JOBS=$(nproc 2>/dev/null || echo 4)
PREFIX="${HOME}/.local"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/tmux"

# ---------- 解析参数 ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--clean)   CLEAN=1 ;;
    -i|--install) INSTALL=1 ;;
    -j)           shift; JOBS="$1" ;;
    -h|--help)
      sed -n '3,9p' "$0" | sed 's/^# //;s/^#//'
      exit 0 ;;
    *) die "未知参数: $1，使用 -h 查看帮助" ;;
  esac
  shift
done

# ---------- 环境检查 ----------
info "检查编译环境..."
for cmd in gcc make autoconf automake pkg-config bison; do
  command -v "$cmd" &>/dev/null || die "缺少依赖：$cmd（请先运行 sudo apt install build-essential autoconf automake pkgconf bison）"
done
for lib in libevent ncurses; do
  pkg-config --exists "$lib" 2>/dev/null || \
  pkg-config --exists "${lib}_core" 2>/dev/null || \
  pkg-config --exists "ncursesw" 2>/dev/null || \
  ldconfig -p 2>/dev/null | grep -q "$lib" || \
  warn "未检测到 $lib，编译可能失败（sudo apt install libevent-dev libncurses-dev）"
done
ok "环境检查通过（gcc=$(gcc --version | head -1 | awk '{print $3}'), jobs=${JOBS}）"

# ---------- 进入源码目录 ----------
[[ -d "$SRC_DIR" ]] || die "源码目录不存在：$SRC_DIR"
cd "$SRC_DIR"

CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD)
info "源码目录：$SRC_DIR（当前版本：$CURRENT_TAG）"

# ---------- 清理 ----------
if [[ $CLEAN -eq 1 ]]; then
  info "清理上次构建产物..."
  [[ -f Makefile ]] && make clean -s || true
  ok "清理完成"
fi

# ---------- autogen ----------
if [[ ! -f configure ]]; then
  info "运行 autogen.sh 生成 configure..."
  sh autogen.sh
  ok "autogen 完成"
else
  info "configure 已存在，跳过 autogen（使用 -c 强制重新生成）"
fi

# ---------- configure ----------
info "配置构建（prefix=${PREFIX}）..."
./configure \
  --prefix="${PREFIX}" \
  --enable-static=no \
  2>&1 | grep -E '(checking for libevent|checking for tinfo|checking platform|error:|configure:)' || true
ok "configure 完成"

# ---------- make ----------
info "开始编译（-j${JOBS}）..."
START_TS=$(date +%s)
make -j"${JOBS}"
END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))
ok "编译完成（耗时 ${ELAPSED}s）"

# ---------- 二进制信息 ----------
BINARY="${SRC_DIR}/tmux"
[[ -f "$BINARY" ]] || die "未找到编译产物：$BINARY"
BINARY_SIZE=$(du -sh "$BINARY" | cut -f1)
BINARY_VERSION=$("$BINARY" -V)
info "二进制：$BINARY（${BINARY_SIZE}）"
ok "版本验证：${BINARY_VERSION}"

# ---------- 安装 ----------
if [[ $INSTALL -eq 1 ]]; then
  info "安装到 ${PREFIX}/bin/tmux..."
  mkdir -p "${PREFIX}/bin"
  make install -s
  ok "安装完成：${PREFIX}/bin/tmux"
  if ! echo "$PATH" | grep -q "${PREFIX}/bin"; then
    warn "请将 ${PREFIX}/bin 加入 PATH："
    warn "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
  fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  构建成功：${BINARY_VERSION}${NC}"
echo -e "${GREEN}  二进制：  ${BINARY}${NC}"
if [[ $INSTALL -eq 1 ]]; then
echo -e "${GREEN}  已安装：  ${PREFIX}/bin/tmux${NC}"
fi
echo -e "${GREEN}========================================${NC}"
