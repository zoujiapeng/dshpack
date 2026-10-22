#!/data/data/com.termux/files/usr/bin/bash
# bootstrap.sh — 全新 Termux 上一键装出 dsh + dshpj（+ 可选地从旧机的包还原整机环境）。
#
#   bash bootstrap.sh                                   # 只装 dsh + dshpj + dshpack
#   bash bootstrap.sh --bundle http://ip:8899/x.run     # 再从旧机的快照包还原（推荐）
#   bash bootstrap.sh --bundle /sdcard/Download/x.tar.zst
#   DSH_VER=0.2.0-rc.2 bash bootstrap.sh                # 锁定 dsh 版本（默认见下）
#   bash bootstrap.sh --minimal                         # 不装 dshpj，只装 dsh + dshpack
#
# 这个脚本是给"手机上只有 opencode（或其他 AI 代理）"的场景写的：它自己把
# 前置条件、版本、校验都处理掉，代理只需要执行它，然后看最后的自检输出。
set -euo pipefail

DSH_VER="${DSH_VER:-0.2.0-rc.2}"
DSHPJ_REPO="${DSHPJ_REPO:-https://raw.githubusercontent.com/zoujiapeng/dshpj-installer/main}"
DSHPACK_RAW="${DSHPACK_RAW:-https://raw.githubusercontent.com/zoujiapeng/dshpack/main/dshpack}"
BUNDLE=""
MINIMAL=0
PKGS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --bundle) BUNDLE="${2:?}"; shift 2;;
    --bundle=*) BUNDLE="${1#*=}"; shift;;
    --minimal) MINIMAL=1; shift;;
    --pkgs) PKGS=1; shift;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "未知参数: $1" >&2; exit 2;;
  esac
done

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
say() { printf '\n\033[1;36m[bootstrap]\033[0m %s\n' "$*"; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$*"; }
die() { printf '\n[bootstrap] 失败: %s\n' "$*" >&2; exit 1; }

# root 逃逸（与 dsh / dshui 相同的 Magisk su 路径；无 root 机器会直接跳过）
if [ "$(id -u)" != "0" ] && [ -n "${DSHPACK_AS_ROOT:-}" ] && command -v su >/dev/null 2>&1; then
  exec su -c "$(printf '%q ' "$0" "$@")"
fi

case "$(uname -o 2>/dev/null || uname -s)" in
  Android) : ;;
  *) say "非 Android/Termux 环境，脚本仍会尝试继续（前缀 $PREFIX）" ;;
esac
[ -d "$PREFIX" ] || die "找不到 Termux 前缀 $PREFIX"
say "目标: $PREFIX  |  home: $HOME_DIR  |  架构: $(uname -m)"

# ---------------------------------------------------------------- 1. 前置包 ---
say "1/5 安装前置包"
MISSING=""
for c in node npm tar zstd curl git; do command -v "$c" >/dev/null 2>&1 || MISSING="$MISSING $c"; done
if [ -n "$MISSING" ]; then
  say "缺少:$MISSING —— pkg install"
  command -v pkg >/dev/null 2>&1 || die "没有 pkg 命令，这不是 Termux"
  pkg install -y nodejs-lts tar zstd curl git openssl termux-exec || pkg install -y nodejs tar zstd curl git openssl termux-exec
fi
for c in node npm tar zstd curl git; do command -v "$c" >/dev/null 2>&1 && ok "$c $(  [ "$c" = node ] && node -v || true)"; done
command -v node >/dev/null || die "node 装失败"

# ---------------------------------------------------------------- 2. dsh ---
say "2/5 安装 @deepseek-ai/dsh@$DSH_VER"
if [ -f "$PREFIX/lib/node_modules/@deepseek-ai/dsh/package.json" ] && \
   grep -q "\"version\": \"$DSH_VER\"" "$PREFIX/lib/node_modules/@deepseek-ai/dsh/package.json" 2>/dev/null; then
  ok "已装 $DSH_VER，跳过"
else
  npm i -g "@deepseek-ai/dsh@$DSH_VER"
  ok "dsh $(node -e 'const fs=require("fs");console.log(JSON.parse(fs.readFileSync(process.argv[1],"utf8")).version)' "$PREFIX/lib/node_modules/@deepseek-ai/dsh/package.json")"
fi

# ---------------------------------------------------------------- 3. dshpj ---
if [ "$MINIMAL" = 0 ]; then
  say "3/5 安装 dshpj 补丁栈（~/.dshpj + \$PREFIX/bin/dshpj）"
  if [ -f "$HOME_DIR/.dshpj/assets/patch.yml" ]; then
    ok "已存在 ~/.dshpj/assets/patch.yml，跳过"
  else
    curl -fsSL "$DSHPJ_REPO/bootstrap.sh" -o "$PREFIX/tmp/dshpj-bootstrap.sh" || die "下载 dshpj bootstrap.sh 失败（网络？）"
    bash "$PREFIX/tmp/dshpj-bootstrap.sh"
    [ -f "$HOME_DIR/.dshpj/assets/patch.yml" ] && ok "补丁栈就绪" || die "dshpj 安装后仍找不到 patch.yml"
  fi
else
  say "3/5 跳过 dshpj（--minimal）"
fi

# ---------------------------------------------------------------- 4. dshpack ---
say "4/5 安装 dshpack"
curl -fsSL "$DSHPACK_RAW" -o "$PREFIX/bin/dshpack" || die "下载 dshpack 失败"
chmod 755 "$PREFIX/bin/dshpack"
ok "dshpack $("$PREFIX/bin/dshpack" info | head -1 | awk '{print $2}')"

# ---------------------------------------------------------------- 5. 还原 ---
if [ -n "$BUNDLE" ]; then
  say "5/5 从快照包还原"
  mkdir -p "$HOME_DIR/dshpack-in"
  case "$BUNDLE" in
    http://*|https://*)
      out="$HOME_DIR/dshpack-in/$(basename "${BUNDLE%%\?*}")"
      say "下载 $BUNDLE"
      curl -fL --progress-bar "$BUNDLE" -o "$out" || die "下载失败"
      ;;
    *) out="$BUNDLE";;
  esac
  [ -f "$out" ] || die "找不到包: $out"
  ok "包: $out ($(du -h "$out" | cut -f1))"
  if [ "$PKGS" = 1 ]; then
    bash "$PREFIX/bin/dshpack" restore "$out" --pkgs
  else
    bash "$PREFIX/bin/dshpack" restore "$out"
  fi
else
  say "5/5 未给 --bundle，跳过整机还原（只做了干净的 dsh + dshpj 安装）"
fi

# ---------------------------------------------------------------- 自检 ---
say "自检"
printf '  %-12s %s\n' "node" "$(node -v)"
printf '  %-12s %s\n' "dsh"  "$(node -e 'const fs=require("fs");try{console.log(JSON.parse(fs.readFileSync(process.argv[1],"utf8")).version)}catch(e){console.log("缺失")}' "$PREFIX/lib/node_modules/@deepseek-ai/dsh/package.json")"
printf '  %-12s %s\n' "dshpj" "$([ -x "$PREFIX/bin/dshpj" ] && echo "$PREFIX/bin/dshpj" || echo "未安装")"
printf '  %-12s %s\n' "patch.yml" "$([ -f "$HOME_DIR/.dshpj/assets/patch.yml" ] && echo "就绪" || echo "缺失")"
printf '  %-12s %s\n' "~/.dsh" "$(du -sh "$HOME_DIR/.dsh" 2>/dev/null | cut -f1 || echo 未还原)"
printf '  %-12s %s\n' "dshpack" "$(command -v dshpack || echo 缺失)"

cat <<'DONE'

下一步
  dshpj                     # 起带补丁的 web UI（局域网 + 二维码）
  dsh --version             # 只想验证原版 dsh
  dshpack info              # 看本机环境指纹

如果这是新机、想和旧机一模一样，旧机上先跑：
  dshpack serve             # 打印 http://<ip>:8899/ 和二维码
然后在新机重跑：
  bash bootstrap.sh --bundle http://<ip>:8899/dshpack-xxx.run
DONE
