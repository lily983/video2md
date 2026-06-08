#!/usr/bin/env python3
# fw_transcribe.py — 用 faster-whisper 转录音频,产出 WEBVTT(供 video_to_md.sh 的组装器消费)
# 用法: python fw_transcribe.py <音频文件> <输出.vtt> <模型名> [语言(留空=自动)]
# 设备/精度可用环境变量覆盖: FW_DEVICE=cuda|cpu|auto  FW_COMPUTE=float16|int8_float16|int8
# CUDA 初始化失败(如 Blackwell 兼容问题)会自动回退 CPU/int8。
import os
import sys

audio = sys.argv[1]
out_vtt = sys.argv[2]
model_name = sys.argv[3]
lang = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4].strip() else None

from faster_whisper import WhisperModel

device = os.environ.get("FW_DEVICE", "auto")
compute = os.environ.get("FW_COMPUTE", "float16")


def load_model():
    if device in ("auto", "cuda"):
        try:
            return WhisperModel(model_name, device="cuda", compute_type=compute)
        except Exception as e:
            sys.stderr.write(f">> CUDA 初始化失败({e}); 回退 CPU/int8。\n")
    return WhisperModel(model_name, device="cpu", compute_type="int8")


model = load_model()
segments, info = model.transcribe(audio, language=lang, vad_filter=False)


def ts(sec):
    sec = max(0.0, float(sec or 0.0))
    h = int(sec // 3600)
    m = int((sec % 3600) // 60)
    s = sec % 60
    return f"{h:02d}:{m:02d}:{s:06.3f}"


with open(out_vtt, "w", encoding="utf-8") as f:
    f.write("WEBVTT\n\n")
    for seg in segments:
        text = (seg.text or "").strip()
        if not text:
            continue
        f.write(f"{ts(seg.start)} --> {ts(seg.end)}\n{text}\n\n")

sys.stderr.write(f">> faster-whisper 转录完成(检测语言={info.language}, 概率={info.language_probability:.2f})。\n")
