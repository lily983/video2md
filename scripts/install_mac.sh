#!/usr/bin/env bash
# install_mac.sh — macOS (Apple Silicon) 一次性安装脚本,幂等(可重复跑)
# 装:Homebrew(若无则提示) → ffmpeg / yt-dlp / whisper-cpp → 下载 whisper.cpp GGML 模型
# 可选环境变量:
#   YT_MODEL=large-v3-turbo | medium | large-v3   默认 large-v3-turbo(质量速度甜点,中英混说也能正确混排)
#   MODEL_DIR=~/whisper-models                    模型存放目录
#   HF_MIRROR=https://hf-mirror.com               国内镜像,默认值即可
set -euo pipefail

MODEL="${YT_MODEL:-large-v3-turbo}"
MODEL_DIR="${MODEL_DIR:-$HOME/whisper-models}"
HF_MIRROR="${HF_MIRROR:-https://hf-mirror.com}"
mkdir -p "$MODEL_DIR"

echo ">> [1/3] 检查 Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
  echo "!! 未检测到 Homebrew。先装 brew 再来一次:" >&2
  echo '   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' >&2
  exit 1
fi
echo "   brew 已装: $(brew --version | head -1)"

echo ">> [2/3] 检查 / 安装 ffmpeg, yt-dlp, whisper-cpp(已装的会跳过)..."
for pkg in ffmpeg yt-dlp whisper-cpp; do
  if brew list "$pkg" >/dev/null 2>&1; then
    echo "   $pkg 已装"
  else
    echo "   安装 $pkg ..."
    brew install "$pkg"
  fi
done

MODEL_FILE="$MODEL_DIR/ggml-${MODEL}.bin"
echo ">> [3/3] 检查 whisper.cpp 模型 ggml-${MODEL}.bin ..."
if [ -f "$MODEL_FILE" ] && [ "$(stat -f%z "$MODEL_FILE" 2>/dev/null || echo 0)" -gt 1000000 ]; then
  echo "   已存在: $MODEL_FILE ($(du -h "$MODEL_FILE" | cut -f1))"
else
  URL="$HF_MIRROR/ggerganov/whisper.cpp/resolve/main/ggml-${MODEL}.bin"
  echo "   从镜像下载: $URL"
  curl -L --fail --progress-bar -o "$MODEL_FILE.tmp" "$URL"
  mv "$MODEL_FILE.tmp" "$MODEL_FILE"
  echo "   下载完成: $(du -h "$MODEL_FILE" | cut -f1)"
fi

cat <<EOF

============================================
安装完成 ✓
模型:    $MODEL_FILE
工具:    $(brew --prefix whisper-cpp)/bin/whisper-cli

用法:    bash video_to_md_mac.sh "<视频链接(YouTube/Bilibili)>" [输出目录]
说明:    video_to_md_mac.sh 会自己处理 GGML_METAL_PATH_RESOURCES,
         不用改 ~/.zshrc。
============================================
EOF
