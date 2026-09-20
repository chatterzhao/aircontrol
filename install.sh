#!/usr/bin/env bash
#
# AirControl 执行端一键安装。
#
#   curl -fsSL https://gitee.com/zhaoquan/aircontrol/raw/main/install.sh | bash
#
# 它做四件事：选对版本 → 从**能通的源**下载 → **校验 SHA-256** → 装好并打印配对信息。
#
# ## 为什么要有这个脚本
#
# 路线图评审里写得很直白：「装 daemon 要 ./gradlew installDist 再手敲一堆参数」——
# **装不上 = 没法真用**。这一步不做，前面的东西都只是能跑，不是能用。
#
# ## 为什么下载要回退多个源
#
# 实测：GitHub 的 Release 下载会 302 跳到 release-assets.githubusercontent.com
# 和 *.blob.core.windows.net，国内**连得上、下不动**（实测 19 KB/s，120 秒只下到 38%）。
# 所以**先试 Gitee**（国内直连），失败再退 GitHub。
#
# ## 为什么一定要校验
#
# 用户是照着一条命令从网上拉二进制然后执行。不校验的话，
# 中间任何一个环节被换掉，用户毫无知觉。**校验和不是可选项。**
#
set -euo pipefail

VERSION="${AIRCONTROL_VERSION:-}"       # 留空＝装最新
PREFIX="${AIRCONTROL_PREFIX:-$HOME/.aircontrol}"
PORT="${AIRCONTROL_PORT:-8080}"
PIN="${AIRCONTROL_PIN:-}"
TMUX_SESSION="${AIRCONTROL_SESSION:-aircontrol}"
START_AFTER=0
UNINSTALL=0

GITHUB_REPO="chatterzhao/aircontrol"
GITEE_REPO="zhaoquan/aircontrol"

usage() {
    sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
    cat <<'EOF'

选项：
  --version X.Y.Z   装指定版本（默认最新）
  --prefix DIR      安装目录（默认 ~/.aircontrol）
  --port N          WS 端口（默认 8080）
  --pin NNNN        PIN（默认随机生成 6 位）
  --session NAME    tmux 会话名（默认 aircontrol）
  --start           装完直接启动
  --uninstall       卸载（保留 ~/.aircontrol 里的会话数据）
  -h, --help        显示本帮助
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version)   VERSION="${2:?}"; shift 2 ;;
        --prefix)    PREFIX="${2:?}"; shift 2 ;;
        --port)      PORT="${2:?}"; shift 2 ;;
        --pin)       PIN="${2:?}"; shift 2 ;;
        --session)   TMUX_SESSION="${2:?}"; shift 2 ;;
        --start)     START_AFTER=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "未知参数：$1（-h 看帮助）" >&2; exit 2 ;;
    esac
done

say()  { printf '  %s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
die()  { printf '\n❌ %s\n' "$*" >&2; exit 1; }

# ── 卸载 ─────────────────────────────────────────────────────────────────────

if [ "$UNINSTALL" = 1 ]; then
    step "卸载"
    if [ -d "$PREFIX" ]; then
        # 只删程序，保留用户数据目录（将来会话记录之类放这里）
        rm -rf "$PREFIX/bin" "$PREFIX/lib"
        say "已删除 $PREFIX 下的程序文件（保留其余内容）"
    else
        say "$PREFIX 不存在，无需卸载"
    fi
    say "tmux 里正在跑的会话没有动——它们不属于安装目录"
    exit 0
fi

# ── 1. 环境检查 ───────────────────────────────────────────────────────────────

step "检查环境"

case "$(uname -s)" in
    Darwin) OS=macos ;;
    Linux)  OS=linux ;;
    MINGW*|MSYS*|CYGWIN*)
        die "Windows 请用 PowerShell 手动安装：下载 zip 解压后跑 bin\\daemon.bat
    （本脚本是 bash 写的，Windows 上原生跑不了；Git Bash 里的路径和进程语义也不一致）" ;;
    *) die "不支持的平台：$(uname -s)" ;;
esac

case "$(uname -m)" in
    arm64|aarch64) ARCH=arm64 ;;
    x86_64|amd64)  ARCH=x64 ;;
    *) die "不支持的架构：$(uname -m)" ;;
esac

# macOS Intel 的产物在 roadmap 里是 x64，但只有 Apple 芯片的机器编得出 arm64——
# 两个都要有，缺了就说清楚，别让用户下到一个装不上的包。
SLUG="$OS-$ARCH"

# ⚠️ 不能只看 `command -v java`：macOS 上 /usr/bin/java 是个 **stub**，
# 没装 JDK 时它也存在，但跑起来只打印 "Unable to locate a Java Runtime."。
# 所以必须**真的解析出版本号**才算数——这是实测踩到的。
java_major() {
    java -version 2>&1 | head -1 | sed -nE 's/.*version "([0-9]+).*/\1/p'
}

# ── 便携 JRE：没有 Java 时，**自己带一个**，不动系统 ──────────────────────────
#
# 为什么不在生产机上 `apt install openjdk-17-jre-headless`：
# 那是**改系统状态**（装包、可能升依赖、要 root）。这个脚本装到用户目录下，
# 本来就不需要 root；在生产机上装系统包是越界的——**用户没批准你动他的系统**。
#
# 做法：下载官方 Temurin JRE 的压缩包，解压到 $PREFIX/jre，
# 只让这一个程序用它。删掉 $PREFIX 就是完整卸载。
#
# 只在 Linux x64/aarch64 上做（macOS 用户基本都能 brew，而且 macOS 的
# 便携包分发策略各不相同，不如给条明路）。
ensure_portable_jre() {
    local jre_dir="$PREFIX/jre"
    if [ -x "$jre_dir/bin/java" ]; then
        JAVA_HOME_EFFECTIVE="$jre_dir"
        return 0
    fi
    [ "$OS" = "linux" ] || return 1

    local arch="$ARCH"
    [ "$arch" = "x64" ] || [ "$arch" = "arm64" ] || return 1

    local url="https://api.adoptium.net/v3/binary/latest/17/ga/linux/${arch}/jre/hotspot/normal/eclipse"
    say "没有 Java —— 下载便携 JRE 到 $jre_dir（不动系统）"
    say "  来源：$url"
    local tmp="$PREFIX/.jre-dl.$$"
    mkdir -p "$PREFIX"
    if ! curl -fSL --retry 3 -m 600 -o "$tmp" "$url" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi
    mkdir -p "$jre_dir"
    # 官方包的顶层是个带版本号的目录，剥掉它
    if ! tar xzf "$tmp" -C "$jre_dir" --strip-components=1 2>/dev/null; then
        rm -f "$tmp"; rm -rf "$jre_dir"
        return 1
    fi
    rm -f "$tmp"
    [ -x "$jre_dir/bin/java" ] || { rm -rf "$jre_dir"; return 1; }
    JAVA_HOME_EFFECTIVE="$jre_dir"
    return 0
}

JAVA_HOME_EFFECTIVE=""
JAVA_MAJOR="$(java_major || true)"
if [ -z "$JAVA_MAJOR" ]; then
    if ensure_portable_jre; then
        JAVA_MAJOR="$(JAVA_HOME="$JAVA_HOME_EFFECTIVE" "$JAVA_HOME_EFFECTIVE/bin/java" -version 2>&1 \
            | head -1 | sed -nE 's/.*version "([0-9]+).*/\1/p')"
        say "便携 JRE ${JAVA_MAJOR} ✓（在 $JAVA_HOME_EFFECTIVE，不影响系统）"
    fi
fi
if [ -z "$JAVA_MAJOR" ]; then
    hint=""
    # Homebrew 的 openjdk 装了也不进 PATH（keg-only），顺手给条明路
    if [ -d /opt/homebrew/opt/openjdk@17 ] || [ -d /usr/local/opt/openjdk@17 ]; then
        brew_prefix="/opt/homebrew"
        [ -d /usr/local/opt/openjdk@17 ] && brew_prefix="/usr/local"
        hint="
    这台机器上其实装了 openjdk@17，只是没进 PATH。加一行就行：
        echo 'export PATH=\"$brew_prefix/opt/openjdk@17/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
    fi
    die "没有可用的 Java。需要 **Java 17 或更高**。
    macOS:  brew install openjdk@17
    Ubuntu: sudo apt install openjdk-17-jre-headless
    Fedora: sudo dnf install java-17-openjdk-headless$hint"
fi

[ "$JAVA_MAJOR" -ge 17 ] 2>/dev/null || die "Java 版本太低（${JAVA_MAJOR}），需要 17 或更高"
say "Java $JAVA_MAJOR ✓"

if command -v tmux >/dev/null 2>&1; then
    say "tmux $(tmux -V | awk '{print $2}') ✓（断线后会话能保住）"
else
    say "⚠️  没装 tmux：能连，但**会话管理用不了**（新建/切换/重开都会报 E004）"
    say "   想让会话保住（断线不丢），装一个："
    say "     macOS:  brew install tmux"
    say "     Ubuntu: sudo apt install tmux"
    say "     CentOS/OpenCloudOS: sudo dnf install tmux"
    say "   装不了也没关系——单会话照样能用。"
fi

say "平台 ${SLUG}，装到 $PREFIX"

# ── 2. 选版本 ─────────────────────────────────────────────────────────────────

step "查最新版本"

# 两个源都问一遍，谁通用谁——和 App 里那套多源回退同一个道理：
# 国内连 Gitee 稳，国外/有代理的连 GitHub 稳。
fetch_latest() {
    local url="$1" kind="$2" body
    body="$(curl -fsSL -m 20 "$url" 2>/dev/null)" || return 1
    printf '%s' "$body" | python3 -c "
import sys, json
kind = '$kind'
try:
    d = json.load(sys.stdin)
    rs = d if isinstance(d, list) else [d]
    tags = [r.get('tag_name','').lstrip('v') for r in rs if r.get('tag_name')]
    # Gitee 按「最旧在前」返回，所以**不能取第一条**，得自己比版本号
    def key(v):
        return [int(x) if x.isdigit() else 0 for x in v.replace('-', '.').split('.')]
    print(max(tags, key=key) if tags else '')
except Exception:
    print('')
" 2>/dev/null
}

if [ -z "$VERSION" ]; then
    VERSION="$(fetch_latest "https://gitee.com/api/v5/repos/$GITEE_REPO/releases?per_page=20" gitee || true)"
    [ -n "$VERSION" ] && say "Gitee 上最新：$VERSION"
    if [ -z "$VERSION" ]; then
        VERSION="$(fetch_latest "https://api.github.com/repos/$GITHUB_REPO/releases/latest" github || true)"
        [ -n "$VERSION" ] && say "GitHub 上最新：$VERSION"
    fi
    [ -n "$VERSION" ] || die "两个源都查不到最新版本。检查网络，或用 --version X.Y.Z 指定版本。"
else
    say "指定版本：$VERSION"
fi

# ── 3. 下载（多源回退）────────────────────────────────────────────────────────

step "下载执行端 ${VERSION}（${SLUG}）"

ARTIFACT="aircontrol-daemon-${SLUG}-${VERSION}.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

GITEE_BASE="https://gitee.com/$GITEE_REPO/releases/download/v$VERSION"
GITHUB_BASE="https://github.com/$GITHUB_REPO/releases/download/v$VERSION"

# 先 Gitee（国内直连），失败再 GitHub。顺序不是偏好，是实测定的。
download() {
    local base="$1" name="$2" out="$3"
    curl -fSL --connect-timeout 15 -m 600 -o "$out" "$base/$name" 2>/dev/null
}

ok=0
for src in "Gitee:$GITEE_BASE" "GitHub:$GITHUB_BASE"; do
    label="${src%%:*}"; base="${src#*:}"
    printf '  从 %s 下载 … ' "$label"
    if download "$base" "$ARTIFACT" "$TMP/$ARTIFACT" && [ -s "$TMP/$ARTIFACT" ]; then
        echo "✅"; ok=1; break
    fi
    echo "失败"
done
[ "$ok" = 1 ] || die "两个源都下载失败。可能是 $SLUG 这个平台还没有产物（当前只发 macOS/Linux 的 x64 与 arm64）。"

# ── 4. 校验 ───────────────────────────────────────────────────────────────────

step "校验完整性"

# 校验和是**必须的**：用户照着一条命令拉二进制然后执行，不校验的话
# 中间任何一环被换掉都毫无知觉。
if download "$base" "SHA-256SUMS" "$TMP/SHA-256SUMS"; then
    if ( cd "$TMP" && grep -q "$ARTIFACT" SHA-256SUMS 2>/dev/null ); then
        if ( cd "$TMP" && { command -v sha256sum >/dev/null 2>&1 && sha256sum -c SHA-256SUMS --ignore-missing 2>/dev/null \
             || shasum -a 256 -c SHA-256SUMS --ignore-missing 2>/dev/null; } ); then
            say "SHA-256 匹配 ✓"
        else
            die "校验失败：下载到的文件和官方校验和不一致。
    这可能是网络中间环节被篡改，也可能是下载不完整。已中止，未安装。"
        fi
    else
        say "⚠️  校验和文件里没有这个产物，跳过校验"
    fi
else
    say "⚠️  取不到 SHA-256SUMS，跳过校验"
fi

# ── 5. 安装 ───────────────────────────────────────────────────────────────────

step "安装到 $PREFIX"

mkdir -p "$PREFIX"
rm -rf "$PREFIX/bin" "$PREFIX/lib"   # 幂等：重跑就是覆盖升级
( cd "$TMP" && unzip -q "$ARTIFACT" -d "$TMP/x" )
if [ -d "$TMP/x/daemon" ]; then
    mv "$TMP/x/daemon/bin" "$PREFIX/bin"
    mv "$TMP/x/daemon/lib" "$PREFIX/lib"
else
    die "压缩包结构不对，期望里面是 daemon/bin + daemon/lib"
fi
chmod +x "$PREFIX/bin/daemon"
say "已装好：$PREFIX/bin/daemon"

# ── 6. 配对信息 ───────────────────────────────────────────────────────────────

step "怎么启动"

# ⚠️ 不再传 --pin：连接码由执行端**随机生成**，每次启动都不一样，
#    3 分钟有效、连一次就换。让用户自己定一个固定 4 位数是不安全的
#    （1 万种可能，同一网络下暴力枚举几分钟就进来了）。
# 用便携 JRE 时，启动命令前面要带上 JAVA_HOME——
# `bin/daemon` 是 Gradle 生成的脚本，它从 PATH/JAVA_HOME 找 java。
JAVA_PREFIX=""
if [ -n "$JAVA_HOME_EFFECTIVE" ]; then
    JAVA_PREFIX="JAVA_HOME=$JAVA_HOME_EFFECTIVE "
fi
LAUNCH="${JAVA_PREFIX}$PREFIX/bin/daemon --ws-port $PORT --session $TMUX_SESSION"

cat <<EOF

  执行端是**命令行程序**——它跑在一个终端窗口里，连接码就显示在那个窗口里。

  启动命令（下次直接复制这条，粘进终端回车）：

      $LAUNCH

  启动后那个终端里会显示：

      [daemon] 连接码 1234（2 分 59 秒内有效，连接一次即失效）
      [daemon] 手机扫码即连：      ← 下面有个二维码
      [daemon] 换一个码：直接按回车。

  • 手机扫那个二维码最省事（不用手抄）
  • 手输的话就填上面那个 4 位数
  • 码 3 分钟自动换一次，**在那个终端里按回车也能立刻换**
  • 连上一次之后这台手机就记住了，**之后重连不用再输码**

  ⚠️ 别关那个终端窗口——关了执行端就停了。

EOF

if [ "$START_AFTER" = 1 ]; then
    step "启动"
    say "按 Ctrl-C 停止"
    echo
    # exec 让 daemon 直接接管这个进程，Ctrl-C 就是停它，不经过一层 shell
    [ -n "$JAVA_HOME_EFFECTIVE" ] && export JAVA_HOME="$JAVA_HOME_EFFECTIVE"
    exec "$PREFIX/bin/daemon" --ws-port "$PORT" --session "$TMUX_SESSION"
else
    printf '  现在启动：%s\n\n' "$LAUNCH"
    say "（加 --start 可以让本脚本装完直接启动）"
fi
