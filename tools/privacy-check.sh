#!/bin/bash
# 提交前的隐私体检。
#
# 存在的理由：这个仓库里的源码同时是「给用户的示例数据」和「我自己的测试素材」，
# 随手把真实信息写进单元测试、示例日记、设置页提示里，肉眼很难发现 ——
# 但一旦 push 就公开了（GitHub 上删文件不等于删历史，还得 rewrite）。
# 所以把检查固定成一条命令，每次 push 前跑一遍，而不是靠记性。
#
#   ./tools/privacy-check.sh
#
# 退出码非 0 = 有问题，别提交。

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 只检查**会被提交**的文件（已跟踪的 + 新加的，但排除 .gitignore 里的）
#
# 要把本脚本自己排除掉：下面的关键词表里就写着那些敏感词，
# 不排除的话它每次都先举报自己一遍。
SELF="tools/privacy-check.sh"
FILES=()
while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] && [ "$f" != "$SELF" ] && FILES+=("$f")
done < <(git ls-files --cached --others --exclude-standard)

if [ ${#FILES[@]} -eq 0 ]; then
    echo "没有可检查的文件。"
    exit 0
fi

echo "▶︎ 隐私体检（${#FILES[@]} 个文件）"
echo

BAD=0

# ── 一、绝不能出现的：真实身份、住址、家人、身体数据 ──
#
# 说明：`com.meiling.riji` 这个 Bundle ID 是**故意保留**的。
# 它决定 UserDefaults 归属和保险库密钥派生，改了等于换一个 App，
# 已安装用户的配置和密钥会读不到 —— 权衡之后保留，不列入检查。
FORBIDDEN=(
    "小竹|昵称"
    "小岚|本名"
    "某县|老家"
    "某新区|老家"
    "某淀|老家"
    "某城|老家"
    "体重|身体数据"
    "斤|身体数据"
    "姐姐|家人"
    "张老板|同事/上级"
    "朱老板|前雇主"
)
echo "── 真实身份 / 住址 / 身体数据 ──"
for pair in "${FORBIDDEN[@]}"; do
    kw="${pair%%|*}"
    why="${pair##*|}"
    hit="$(grep -n -I -- "$kw" "${FILES[@]}" 2>/dev/null || true)"
    if [ -n "$hit" ]; then
        # 变量一定要写成 ${kw}：macOS 自带的是 bash 3.2，
        # 紧跟在变量名后面的多字节汉字会被它当成变量名的一部分（报 unbound variable）。
        echo "  ✗ 「${kw}」（${why}）"
        echo "$hit" | sed 's/^/      /'
        BAD=1
    fi
done
[ "$BAD" = 0 ] && echo "  ✓ 干净"

# ── 二、凭据类：任何看起来像密钥的字符串 ──
echo
echo "── 密钥 / 令牌 ──"
SECRETS='sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[0-9A-Za-z_-]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|Bearer [A-Za-z0-9._-]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
hit="$(grep -n -I -E -- "$SECRETS" "${FILES[@]}" 2>/dev/null || true)"
if [ -n "$hit" ]; then
    echo "  ✗ 疑似硬编码凭据"
    echo "$hit" | sed 's/^/      /'
    BAD=1
else
    echo "  ✓ 干净"
fi

# ── 三、本机路径 / 内网地址 ──
echo
echo "── 本机绝对路径 / 内网地址 ──"
LOCAL='(/Users|/home)/[a-zA-Z][a-zA-Z0-9_-]{1,}/|(10|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
hit="$(grep -n -I -E -- "$LOCAL" "${FILES[@]}" 2>/dev/null \
    | grep -v -E '/(tmp|example|path|user|you|yourname|username)/' || true)"
if [ -n "$hit" ]; then
    echo "  ✗ 出现了具体用户目录或内网地址"
    echo "$hit" | sed 's/^/      /'
    BAD=1
else
    echo "  ✓ 干净"
fi

# ── 四、要求：这些是作者**主动公开**的，出现了是正常的 ──
#
# 只提醒，不拦。要是哪天它们无故消失了，说明可能误删了「关于」页的数据。
echo
echo "── 主动公开的作者信息（应当存在，仅提示）──"
for kw in "Miki Zhu" "750856902@qq.com" "mikizhu520" "逍遥小斑鸠"; do
    n="$(grep -l -I -- "$kw" "${FILES[@]}" 2>/dev/null | wc -l | tr -d ' ')"
    echo "  · $kw → $n 个文件"
done

echo
if [ "$BAD" = 0 ]; then
    echo "✓ 体检通过，可以提交。"
    exit 0
else
    echo "✗ 发现问题，先处理掉再提交。"
    exit 1
fi
