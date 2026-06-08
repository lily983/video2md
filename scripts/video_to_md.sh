#!/usr/bin/env bash
# video_to_md.sh — Video2MD: 跨平台视频→Markdown
#   macOS (Apple Silicon): whisper.cpp + Metal(经 Homebrew)
#   Linux:                 faster-whisper(pip venv,预编译 CUDA,只依赖 NVIDIA 驱动,免 sudo)
# 支持 YouTube 与哔哩哔哩(Bilibili)。用法: bash video_to_md.sh <视频链接> [输出目录]
# 有字幕 → 用字幕;无字幕 → 本地转录。产出单个 .md。
# 缺依赖/缺模型时按系统自动调用 install_mac.sh / install_linux.sh,无需手动预装。
# 可选环境变量:
#   YT_MODEL=large-v3-turbo | medium | large-v3   默认 large-v3-turbo
#   MODEL_DIR=~/whisper-models                    (仅 macOS)ggml 模型目录
#   FW_MODEL / VIDEO2MD_VENV / FW_DEVICE / FW_COMPUTE   (仅 Linux,见 install_linux.sh / fw_transcribe.py)
#   YT_LANG                                       留空(默认)=自动检测语言,不预设
#   YT_BROWSER=safari|chrome|firefox|brave|edge   用浏览器 cookie(B 站通常必需以绕过 412;先关该浏览器)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

URL="${1:?用法: bash video_to_md.sh <视频链接(YouTube/Bilibili)> [输出目录]}"
OUTDIR="${2:-.}"; mkdir -p "$OUTDIR"
MODEL="${YT_MODEL:-large-v3-turbo}"
MODEL_DIR="${MODEL_DIR:-$HOME/whisper-models}"
MODEL_FILE="$MODEL_DIR/ggml-${MODEL}.bin"
VENV_DIR="${VIDEO2MD_VENV:-$HOME/.local/share/video2md/venv}"
FW_MODEL="${FW_MODEL:-$MODEL}"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

run_installer() {  # $1=安装脚本名 $2=失败提示
  if [ ! -f "$SCRIPT_DIR/$1" ]; then
    echo "!! 找不到 $SCRIPT_DIR/$1,无法自动安装。" >&2; exit 1
  fi
  echo ">> 检测到缺少依赖或模型,自动安装(首次稍久)..." >&2
  YT_MODEL="$MODEL" MODEL_DIR="$MODEL_DIR" FW_MODEL="$FW_MODEL" VIDEO2MD_VENV="$VENV_DIR" \
    bash "$SCRIPT_DIR/$1" >&2 || { echo "!! 自动安装失败($2)。请按上方提示处理后重试。" >&2; exit 1; }
}

# ---- 平台相关初始化:工具路径、依赖自检、加速标签 ----
case "$OS" in
  Darwin)
    YTDLP="yt-dlp"; ASM_PY="python3"
    ensure_deps() {
      local need=0 c
      for c in ffmpeg yt-dlp whisper-cli; do command -v "$c" >/dev/null 2>&1 || need=1; done
      [ -f "$MODEL_FILE" ] || need=1
      [ "$need" -eq 0 ] || run_installer install_mac.sh "未装 Homebrew"
    }
    # Metal 资源路径(没设的话 whisper.cpp 会明显变慢)
    if command -v brew >/dev/null 2>&1; then
      BREW_WC="$(brew --prefix whisper-cpp 2>/dev/null || true)"
      [ -n "$BREW_WC" ] && export GGML_METAL_PATH_RESOURCES="$BREW_WC/share/whisper-cpp"
    fi
    ACCEL="Metal"
    ;;
  Linux)
    YTDLP="$VENV_DIR/bin/yt-dlp"; ASM_PY="$VENV_DIR/bin/python"
    ensure_deps() {
      local need=0
      [ -x "$VENV_DIR/bin/yt-dlp" ] || need=1
      "$VENV_DIR/bin/python" -c "import faster_whisper" >/dev/null 2>&1 || need=1
      [ "$need" -eq 0 ] || run_installer install_linux.sh "缺 python3 或网络问题"
    }
    if command -v nvidia-smi >/dev/null 2>&1; then ACCEL="CUDA/GPU(faster-whisper)"; else ACCEL="CPU(faster-whisper)"; fi
    ;;
  *)
    echo "!! 暂不支持的系统: $OS(仅 macOS / Linux)。" >&2; exit 1;;
esac
ensure_deps

# Cookie 策略:
#   YT_BROWSER=none       → 明确不带 cookie(测试公开视频/不登录)
#   YT_BROWSER=<浏览器>    → 用该浏览器 cookie(safari/chrome/firefox/brave/edge)
#   未设 + B 站链接        → 默认尝试 Chrome(B 站常需登录绕过 412);失败会自动改无 cookie 重试
if [ "${YT_BROWSER:-}" = "none" ]; then
  YT_BROWSER=""
elif [ -z "${YT_BROWSER:-}" ] && printf '%s' "$URL" | grep -qiE 'bilibili\.com|b23\.tv'; then
  YT_BROWSER=chrome
  echo ">> 检测到 B 站链接,默认尝试 Chrome cookie 绕过 412(失败会自动改无 cookie 重试;YT_BROWSER=firefox/edge/... 指定,YT_BROWSER=none 禁用)。" >&2
fi
COOKIES=(); [ -n "${YT_BROWSER:-}" ] && COOKIES=(--cookies-from-browser "$YT_BROWSER")

fetch_meta() {  # 用当前 COOKIES 抓元数据与字幕
  "$YTDLP" --skip-download --write-info-json --write-subs --write-auto-subs \
    --sub-langs "zh-Hans,zh,en,en-orig,en-US" --sub-format vtt \
    --sleep-requests 1.5 --retries 10 --extractor-retries 5 --retry-sleep 5 \
    --ignore-errors ${COOKIES[@]+"${COOKIES[@]}"} \
    -o "$WORK/%(id)s.%(ext)s" "$URL" >&2 || echo ">> yt-dlp 部分失败,继续..." >&2
}

echo ">> [1/4] 抓元数据与字幕(不下视频)..." >&2
fetch_meta
INFO=$(ls "$WORK"/*.info.json 2>/dev/null | head -1 || true)
# 带 cookie 却没抓到(常见:该浏览器没装/没登录/cookie 读取失败)→ 自动改无 cookie 重试,公开视频仍可成功
if [ -z "$INFO" ] && [ ${#COOKIES[@]} -gt 0 ]; then
  echo ">> 带 cookie 抓取失败,改用无 cookie 重试(公开视频可行)..." >&2
  COOKIES=(); fetch_meta
  INFO=$(ls "$WORK"/*.info.json 2>/dev/null | head -1 || true)
fi
[ -z "$INFO" ] && { echo "!! 没抓到元数据。B 站若 412:用 YT_BROWSER=<已登录 B 站的浏览器> 重试(先关该浏览器)。" >&2; exit 1; }
VID=$(basename "$INFO" .info.json)

shopt -s nullglob; SUBS=("$WORK/$VID."*.vtt); shopt -u nullglob

if [ ${#SUBS[@]} -eq 0 ]; then
  echo ">> 未发现字幕,进入本地转录流程($MODEL,$ACCEL)。" >&2
  echo ">> [2/4] 下载音频..." >&2
  "$YTDLP" -f bestaudio --sleep-requests 1.5 --retries 10 --extractor-retries 5 \
    --retry-sleep 5 --ignore-errors ${COOKIES[@]+"${COOKIES[@]}"} \
    -o "$WORK/$VID.%(ext)s" "$URL" >&2 || true
  AUDIO=$(ls "$WORK/$VID".* 2>/dev/null | grep -viE '\.(info\.json|vtt|wav)$' | head -1 || true)
  if [ -z "$AUDIO" ]; then
    echo "!! 音频没下到(可能限流);试试 YT_BROWSER=<浏览器>。" >&2
  else
    echo ">> [3/4] 转录中..." >&2
    LANG_OPT="${YT_LANG:-}"
    if [ "$OS" = "Darwin" ]; then
      # macOS: ffmpeg 转 16k 单声道 wav + whisper.cpp(Metal)
      ffmpeg -nostdin -loglevel error -y -i "$AUDIO" -ar 16000 -ac 1 "$WORK/$VID.wav" >&2
      THREADS=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
      WL=(); [ -n "$LANG_OPT" ] && WL=(-l "$LANG_OPT")
      if whisper-cli -m "$MODEL_FILE" -f "$WORK/$VID.wav" \
           -ovtt -of "$WORK/$VID.asr" -t "$THREADS" ${WL[@]+"${WL[@]}"} >&2; then
        echo ">> 转录成功。" >&2
      else
        echo "!! 转录失败,详见上方报错;本次先出无转录文档。" >&2
      fi
    else
      # Linux: faster-whisper(自带 PyAV 解码,无需 ffmpeg)→ 直接产出 .asr.vtt
      if "$VENV_DIR/bin/python" "$SCRIPT_DIR/fw_transcribe.py" \
           "$AUDIO" "$WORK/$VID.asr.vtt" "$FW_MODEL" "$LANG_OPT" >&2; then
        echo ">> 转录成功。" >&2
      else
        echo "!! 转录失败,详见上方报错;本次先出无转录文档。" >&2
      fi
    fi
  fi
fi

echo ">> [4/4] 组装 Markdown..." >&2
"$ASM_PY" - "$WORK" "$OUTDIR" <<'PY'
import sys, os, re, json, glob, html
from datetime import datetime

work, outdir = sys.argv[1], sys.argv[2]
info_files = sorted(glob.glob(os.path.join(work, "*.info.json")), key=os.path.getmtime)
if not info_files:
    sys.exit("找不到 *.info.json。")
info = json.load(open(info_files[-1], encoding="utf-8"))
vid = info.get("id", "")

def hms(sec):
    sec = int(sec or 0); h, m, s = sec // 3600, (sec % 3600) // 60, sec % 60
    return f"{h:02d}:{m:02d}:{s:02d}" if h else f"{m:02d}:{s:02d}"
def yml(v): return '"' + str(v).replace('"', "'").replace("\n", " ").strip() + '"'
def slugify(s, maxlen=50):
    s = (s or "").strip()
    s = re.sub(r'[/\\:\*\?"<>\|\x00-\x1f]', "", s)
    s = re.sub(r"\s+", "-", s); s = re.sub(r"-{2,}", "-", s).strip("-. ")
    if len(s) > maxlen: s = s[:maxlen].rstrip("-. ")
    return s or vid

pref = ["zh-Hans", "zh", "en", "en-orig", "en-US"]
cands = glob.glob(os.path.join(work, f"{vid}.*.vtt"))
def lang_of(p): return os.path.basename(p)[len(vid) + 1:-4]
cands.sort(key=lambda p: pref.index(lang_of(p)) if lang_of(p) in pref else 99)
sub = cands[0] if cands else None
from_asr = bool(sub and sub.endswith(".asr.vtt"))

def _norm(s):
    # 归一化用于比较:压空白、转小写、去首尾标点(中英)
    return re.sub(r"\s+", " ", s or "").strip().lower().strip(".,!?;:。，！？；、…\"'“”‘’ ")

def parse_vtt(path):
    ts_re = re.compile(r"(\d{2}):(\d{2}):(\d{2})\.\d{3}\s*-->")
    cues, cur = [], None
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        m = ts_re.match(line)
        if m:
            h, mn, s = map(int, m.groups()); cur = h*3600 + mn*60 + s; continue
        if (not line or line.startswith(("WEBVTT","Kind:","Language:")) or re.fullmatch(r"\d+", line.strip())):
            continue
        txt = html.unescape(re.sub(r"<[^>]+>", "", line).strip())
        if txt and cur is not None:
            cues.append((cur, txt))
    # 去重:① YouTube 滚动字幕前缀;② 相邻完全相同;③ whisper 重复循环——
    # 同一(较长)句在最近窗口内重复出现就丢弃。短插话(对对对/yeah)不受窗口去重影响。
    clean, recent = [], []
    WIN = 16
    for i, (t, txt) in enumerate(cues):
        n = _norm(txt)
        if i + 1 < len(cues) and cues[i + 1][1].startswith(txt): continue
        if clean and _norm(clean[-1][1]) == n: continue
        if len(n) >= 6 and n in recent: continue
        clean.append((t, txt))
        recent.append(n)
        if len(recent) > WIN: recent.pop(0)
    return clean

def dedup_sentences(text):
    # 段内句级去重:同一(较长)句在最近若干句内重复就丢弃,清掉 whisper 的句子级复读
    parts = re.split(r"(?<=[.!?。！？])\s+", text)
    out, recent = [], []
    for p in parts:
        n = _norm(p)
        if len(n) >= 8 and n in recent:
            continue
        out.append(p)
        recent.append(n)
        if len(recent) > 10: recent.pop(0)
    return " ".join(out)

segments = parse_vtt(sub) if sub else []
chapters = info.get("chapters") or []

def group(segs, chaps):
    out = []
    if chaps:
        for ch in chaps:
            s, e = ch.get("start_time", 0), ch.get("end_time", 1e12)
            txt = dedup_sentences(" ".join(t for (ts, t) in segs if s <= ts < e).strip())
            out.append((s, ch.get("title", ""), txt))
    else:
        buf, start, acc = [], None, 0
        for (ts, t) in segs:
            if start is None: start = ts
            buf.append(t); acc += len(t)
            if acc > 400:
                out.append((start, None, dedup_sentences(" ".join(buf)))); buf, start, acc = [], None, 0
        if buf: out.append((start, None, dedup_sentences(" ".join(buf))))
    return out

blocks = group(segments, chapters)
up = info.get("upload_date", "")
up = f"{up[:4]}-{up[4:6]}-{up[6:]}" if up else ""

L = ["---",
     f"title: {yml(info.get('title',''))}", f"channel: {yml(info.get('uploader',''))}",
     f"url: {yml(info.get('webpage_url',''))}", f"video_id: {yml(vid)}",
     f"upload_date: {yml(up)}", f"duration: {yml(hms(info.get('duration')))}",
     f"saved_at: {yml(datetime.now().strftime('%Y-%m-%d'))}",
     f'transcript_source: "{"asr-whisper" if from_asr else "subtitles"}"',
     'type: "video-transcript"', "---", "",
     f"# {info.get('title','')}", "",
     f"> 来源:{info.get('uploader','')} · {info.get('webpage_url','')}  ",
     "> 该文档为上述视频的转录稿与元数据,供作为模型对话的参考材料。", ""]
if from_asr:
    L += ["> ⚠ 本视频无字幕,转录由本地 whisper 生成,可能存在识别误差。", ""]

desc = html.unescape(info.get("description") or "").strip()
if desc: L += ["## 视频简介", "", desc, ""]
if chapters:
    L += ["## 章节", ""] + [f"- [{hms(c.get('start_time'))}] {c.get('title','')}" for c in chapters] + [""]

L += ["## 转录正文", ""]
if not segments:
    L += ["_未找到字幕,且未生成转录(可能限流、缺依赖或转录失败)。_"]
else:
    for (s, title, txt) in blocks:
        if not txt: continue
        L += [f"### [{hms(s)}] {title}" if title else f"**[{hms(s)}]**", "", txt, ""]

date = datetime.now().strftime("%Y-%m-%d")
field = slugify(os.environ.get("YT_SLUG") or info.get("title", ""))
path = os.path.join(outdir, f"{date}-{field}.md")
open(path, "w", encoding="utf-8").write("\n".join(L))
print(f">> 完成 -> {path}" + ("" if segments else "  (无转录)"), file=sys.stderr)
print(path)
PY
