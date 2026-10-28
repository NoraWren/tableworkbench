#!/usr/bin/env bash
# 录一段演示并转成 GIF（R-REL-03）。两步都在这一个脚本里：先整屏录 mov，再按窗口坐标裁成 GIF。
#
#   ./scripts/record-demo.sh --geometry "566,60,944,546" --seconds 7 --out docs/media/demo.gif
#
# 录的是整屏，事后按 --geometry 裁，坐标单位是屏幕点（脚本自己乘 --scale 换成像素，Retina 填 2）。
# 需要「屏幕录制」权限。倒计时结束才算「开始」，做动作的这 --seconds 秒原样保留；
# 倒计时那段被 --skip 掉（默认等于 --delay），所以动作别抢跑。
#
# 想用已有的 mov 重新出 GIF（调裁剪位置或帧率）：
#   ./scripts/record-demo.sh --from /tmp/rec.mov --skip 2.1 --seconds 7.1 \
#     --geometry "566,60,944,546" --out docs/media/demo.gif
#
# 找屏幕设备号：ffmpeg -f avfoundation -list_devices true -i '' 里 "Capture screen N" 的序号。
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

device=4
geometry=""
seconds=8
fps=12.5
width=820
colors=256
scale=2
delay=3
skip=""
out=""
from=""

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --device) device="$2"; shift 2 ;;
    --geometry) geometry="$2"; shift 2 ;;
    --seconds) seconds="$2"; shift 2 ;;
    --fps) fps="$2"; shift 2 ;;
    --width) width="$2"; shift 2 ;;
    --colors) colors="$2"; shift 2 ;;
    --scale) scale="$2"; shift 2 ;;
    --delay) delay="$2"; shift 2 ;;
    --skip) skip="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --from) from="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数：$1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$out" ] || { echo "缺少 --out" >&2; exit 2; }
[ -n "$geometry" ] || { echo "缺少 --geometry（x,y,w,h，单位是屏幕点）" >&2; exit 2; }
[ -n "$skip" ] || skip="$delay"

command -v ffmpeg >/dev/null || { echo "没装 ffmpeg" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "没装 ffprobe" >&2; exit 1; }

# 点换成像素；crop 的宽高取偶，GIF 与 H.264 都要求。
IFS=',' read -r gx gy gw gh <<<"$geometry"
crop_w=$((gw * scale))
crop_h=$((gh * scale))
crop_w=$((crop_w - crop_w % 2))
crop_h=$((crop_h - crop_h % 2))
crop="crop=${crop_w}:${crop_h}:$((gx * scale)):$((gy * scale))"

if [ -z "$from" ]; then
  from="$(mktemp -t tableworkbench-demo).mov"
  total=$((seconds + delay + 1))
  echo "整屏录制 ${total} 秒，设备 $device，中间文件 $from"
  ffmpeg -v error -y -f avfoundation -framerate 30 -capture_cursor 1 \
    -i "$device:none" -t "$total" -c:v libx264 -preset ultrafast -qp 0 "$from" &
  ffpid=$!
  for i in $(seq "$delay" -1 1); do
    echo "  $i 秒后开始录动作"
    sleep 1
  done
  echo "开始"
  wait "$ffpid"
  echo "录制结束"
else
  echo "用已有录像：$from"
fi

echo "裁剪 ${crop_w}×${crop_h}，${fps} fps，输出宽 ${width}，调色板 ${colors} 色"
ffmpeg -v error -y -ss "$skip" -t "$seconds" -i "$from" \
  -vf "${crop},fps=${fps},scale=${width}:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=${colors}:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a" \
  -loop 0 "$out"

echo "完成：${out}，$(du -h "$out" | cut -f1)，上限 8 MB"
ffprobe -v error -show_entries stream=width,height,nb_frames,r_frame_rate,duration -of default=nw=1 "$out"
