#!/usr/bin/env bash
# dsh-plugin-vision 一键安装脚本（独立版）
#
# 正确挂载方式（与官方 bundle 同锚点，避免 dsh-tools 双实例）：
#   1. 插件实体复制到全局 dsh 依赖树（realpath 在全局树 → 依赖解析单实例）
#   2. 目标 profile 的 node_modules 建软链指向全局树实体
#   3. 清除 profile 里 pnpm 留下的依赖副本，让解析回落到 heal 软链层
#   4. manifest 的 bundles 加名（dependencies 不写 file: 条目）
#
# 用法：./install.sh [profile]     # 默认 web
# 铁律：目标 profile 不能被任何引擎占用（先退出 DSH Desktop / 停掉相关引擎）！
set -euo pipefail

PROFILE="${1:-web}"
PLUGIN_SRC="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_NAME="dsh-plugin-vision"
HOME_DIR="${HOME:-$(getent passwd "$(id -u)" | cut -d: -f6)}"

# 自动探测 dsh 安装位置：从 dsh 可执行文件 realpath 向上找全局依赖树
detect_dsh_dir() {
  local bin=""
  bin="$(command -v dsh 2>/dev/null || true)"
  if [ -z "$bin" ]; then
    for c in "$HOME_DIR/.local/bin/dsh" /usr/local/bin/dsh /usr/bin/dsh; do
      [ -x "$c" ] && bin="$c" && break
    done
  fi
  if [ -z "$bin" ]; then
    echo "❌ 找不到 dsh 可执行文件（请先安装 @deepseek-ai/dsh 或把 dsh 加入 PATH）" >&2
    exit 1
  fi
  local real dir
  real="$(readlink -f "$bin" 2>/dev/null || echo "$bin")"
  dir="$(dirname "$(dirname "$real")")"
  if [ -d "$dir/node_modules" ]; then echo "$dir/node_modules"; else echo "$dir"; fi
}
DSH_NODE_MODULES="$(detect_dsh_dir)"
PROFILE_DIR="$HOME_DIR/.dsh/profiles/$PROFILE"
PROFILE_NM="$PROFILE_DIR/node_modules"

if [ ! -d "$PLUGIN_SRC/lib" ]; then echo "❌ 插件源码不完整：$PLUGIN_SRC"; exit 1; fi
if [ ! -f "$PROFILE_DIR/package.json" ]; then echo "❌ profile 不存在：$PROFILE_DIR"; exit 1; fi

echo "==> 部署 $PLUGIN_NAME → profile [$PROFILE]"
echo "==> dsh 依赖树：$DSH_NODE_MODULES"

# 0. 安全提示：目标 profile 不应有引擎在跑
RUNNING=$(pgrep -af "dsh --profile $PROFILE " | grep -v bwrap | grep -v install.sh || true)
if [ -n "$RUNNING" ]; then
  echo "⚠️  检测到 [$PROFILE] profile 的引擎正在运行："
  echo "$RUNNING"
  echo "    禁止在运行中修改 profile！请先退出应用再执行。"
  exit 1
fi

# 1. 插件实体 → 全局 dsh 依赖树（rsync 同步，含删除，保证与源码一致）
echo "==> 同步插件到全局依赖树：$DSH_NODE_MODULES/$PLUGIN_NAME"
if [ -w "$DSH_NODE_MODULES" ]; then
  mkdir -p "$DSH_NODE_MODULES/$PLUGIN_NAME"
  rsync -a --delete \
    --exclude 'node_modules' --exclude '.git' --exclude 'tests' \
    "$PLUGIN_SRC/" "$DSH_NODE_MODULES/$PLUGIN_NAME/"
else
  echo "==> 全局依赖树不可写（dsh 装在系统目录），改用 sudo…"
  sudo env "HOME=$HOME_DIR" mkdir -p "$DSH_NODE_MODULES/$PLUGIN_NAME"
  sudo env "HOME=$HOME_DIR" rsync -a --delete \
    --exclude 'node_modules' --exclude '.git' --exclude 'tests' \
    "$PLUGIN_SRC/" "$DSH_NODE_MODULES/$PLUGIN_NAME/"
fi

# 2. profile node_modules 软链 → 全局树实体
echo "==> profile 软链：$PROFILE_NM/$PLUGIN_NAME"
mkdir -p "$PROFILE_NM"
rm -rf "$PROFILE_NM/$PLUGIN_NAME"   # 清掉旧副本（实体目录或旧软链）
ln -s "$DSH_NODE_MODULES/$PLUGIN_NAME" "$PROFILE_NM/$PLUGIN_NAME"

# 3. 清除 pnpm 依赖副本（遮蔽 heal 层的元凶），让解析回落到 heal 软链
echo "==> 清除 pnpm 依赖副本（@deepseek-ai/{dsh-tools,schemastery,cosmokit}、@standard-schema）"
for pkg in dsh-tools schemastery cosmokit; do
  rm -rf "$PROFILE_NM/@deepseek-ai/$pkg"
done
rm -rf "$PROFILE_NM/@standard-schema"

# 4. manifest：bundles 追加插件名；dependencies 移除 file: 条目
echo "==> 更新 manifest bundles"
python3 - "$PROFILE_DIR/package.json" "$PLUGIN_NAME" <<'PY'
import json, sys
path, name = sys.argv[1], sys.argv[2]
d = json.load(open(path))
d.setdefault('dsh', {}).setdefault('profile', {}).setdefault('bundles', [])
if name not in d['dsh']['profile']['bundles']:
    d['dsh']['profile']['bundles'].append(name)
d.setdefault('dependencies', {})
d['dependencies'].pop(name, None)  # 删掉 file: 条目，防止 pnpm 重建副本
json.dump(d, open(path, 'w'), indent=2, ensure_ascii=False)
print(f"bundles = {d['dsh']['profile']['bundles']}")
PY

echo "==> 部署完成。重启引擎后生效；配置见 README（settings.yaml 的 vision 段）。"
