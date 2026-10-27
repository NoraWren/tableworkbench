#!/usr/bin/env bash
# 查 .git 里被云盘、备份工具复制出来的「文件名 2」这类副本。
# 它们会被 git 当成非法 ref，任何 fetch、push、status --branch 都会报
# "bad object refs/heads/master 2" 然后失败。
#
# 用法：./scripts/check-git-refs.sh          只列出
#      ./scripts/check-git-refs.sh --move   搬到 /tmp 备份目录
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
backup="/tmp/git-stray-refs-$(date +%Y%m%d-%H%M%S)"

strays=()
while IFS= read -r -d '' path; do
  strays+=("$path")
done < <(find "$root/.git" -type f -name '* [0-9]*' -print0 2>/dev/null)

if [ ${#strays[@]} -eq 0 ]; then
  echo "干净：.git 里没有带空格数字的副本"
  exit 0
fi

echo "发现 ${#strays[@]} 个副本，git 会把它们当成非法 ref："
for path in "${strays[@]}"; do
  echo "  ${path#$root/}"
done

if [ "${1:-}" != "--move" ]; then
  echo
  echo "加 --move 搬到 $backup 之后再执行 git 命令"
  exit 1
fi

mkdir -p "$backup"
for path in "${strays[@]}"; do
  mv "$path" "$backup/$(printf '%s' "${path#$root/.git/}" | tr '/' '_')"
done
echo
echo "已搬到 $backup"
echo "确认没问题后可以整个删掉"
