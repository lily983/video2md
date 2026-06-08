#!/usr/bin/env bash
# install_linux.sh — Video2MD Linux 安装(免 sudo)
# 用 faster-whisper(pip,自带预编译 CUDA wheel,只依赖 NVIDIA 驱动,无需 CUDA toolkit/编译/root)。
# 全部装进用户态 venv;音频解码用 faster-whisper 自带的 PyAV,无需系统 ffmpeg。
# 可选环境变量:
#   YT_MODEL=large-v3-turbo | large-v3 | medium ...   默认 large-v3-turbo
#   FW_MODEL=<faster-whisper 模型名或HF repo>          默认=YT_MODEL;识别不了时用它覆盖
#   VIDEO2MD_VENV=~/.local/share/video2md/venv         venv 位置
#   HF_ENDPOINT=https://hf-mirror.com                  模型下载镜像(国内默认)
set -euo pipefail

MODEL="${YT_MODEL:-large-v3-turbo}"
FW_MODEL="${FW_MODEL:-$MODEL}"
VENV_DIR="${VIDEO2MD_VENV:-$HOME/.local/share/video2md/venv}"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"

PYBIN="$(command -v python3 || true)"
[ -z "$PYBIN" ] && { echo "!! 没有 python3,请先装 python3(用户态发行版自带即可)。" >&2; exit 1; }

echo ">> [1/3] 准备用户态 venv: $VENV_DIR"
if [ ! -x "$VENV_DIR/bin/python" ]; then
  mkdir -p "$(dirname "$VENV_DIR")"
  if "$PYBIN" -m venv "$VENV_DIR" 2>/dev/null; then
    echo "   venv 已建(python -m venv)"
  else
    echo "   python3 -m venv 不可用(可能缺 python3-venv);改用用户态 virtualenv,免 sudo。" >&2
    "$PYBIN" -m pip --version >/dev/null 2>&1 || curl -fsSL https://bootstrap.pypa.io/get-pip.py | "$PYBIN" - --user
    "$PYBIN" -m pip install --user -q virtualenv
    "$PYBIN" -m virtualenv "$VENV_DIR"
  fi
fi
PY="$VENV_DIR/bin/python"

echo ">> [2/3] 安装 faster-whisper + yt-dlp(预编译 CUDA,无需 sudo/CUDA toolkit)..."
"$PY" -m pip install -q --upgrade pip
# secretstorage: yt-dlp 解密 Linux Chrome AES-CBC cookie 必需,不装会大批静默解密失败(SESSDATA 等登录 cookie 丢失,B 站 412)
# httpx[socks] + socksio: 用户机器若设了 SOCKS 代理,huggingface_hub 调用会因缺 socksio 崩溃
"$PY" -m pip install -q --upgrade faster-whisper yt-dlp secretstorage 'httpx[socks]' socksio

echo ">> [3/3] 预下载模型: $FW_MODEL (经 $HF_ENDPOINT)..."
# 用 CPU/int8 仅触发权重下载到 HF 缓存,不占显存;识别不了的模型名给出提示
"$PY" - "$FW_MODEL" <<'PYEOF' || { echo "!! 模型名 '$FW_MODEL' 可能不被 faster-whisper 识别;用 FW_MODEL=<HF仓库或受支持名> 重试(如 large-v3 / deepdml/faster-whisper-large-v3-turbo-ct2)。" >&2; exit 1; }
import sys
from faster_whisper import WhisperModel
m = sys.argv[1]
WhisperModel(m, device="cpu", compute_type="int8")
print("   模型已缓存:", m)
PYEOF

cat <<EOF

============================================
安装完成 ✓ (Linux / faster-whisper, 免 sudo)
venv:    $VENV_DIR
模型:    $FW_MODEL
GPU:     $(command -v nvidia-smi >/dev/null 2>&1 && echo "检测到 NVIDIA → 运行时 device=cuda(预编译 wheel,无需 CUDA toolkit)" || echo "未检测到 NVIDIA → 走 CPU")
用法:    bash video_to_md.sh "<视频链接(YouTube/Bilibili)>" [输出目录]
说明:    转录由 video_to_md.sh 调用本 venv 的 faster-whisper 完成;
         若 CUDA 初始化失败会自动回退 CPU。
============================================
EOF
