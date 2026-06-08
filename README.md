# Video2MD

> **Save videos worth learning from — straight into your knowledge base.** Turn YouTube / Bilibili videos into Markdown notes (YAML frontmatter + chapters + clean transcript) so they compound with everything else you've collected, instead of dying in your watch history. Local Whisper transcription, GPU-accelerated on macOS Apple Silicon and NVIDIA Linux — even subtitle-less videos become searchable text, fully offline.
>
> **把值得学的视频直接存进知识库** —— YouTube / B 站视频一键转成 Markdown 笔记（YAML 元信息 + 章节 + 清洗后转录），让它们和你已收藏的内容一起复利，而不是消失在观看历史里。本地 Whisper 转录（macOS Metal / Linux CUDA 加速），即使视频没字幕也能完全离线转成可搜索文本。
>
> Standalone shell script or [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) skill — both supported. 独立脚本或 Claude Code skill 两种用法皆可。

## Features

- **Cross-platform** — macOS (Apple Silicon, Metal GPU via `whisper.cpp`) / Linux (NVIDIA CUDA or CPU via `faster-whisper`). Script auto-detects via `uname`.
- **No subtitles? Local transcription.** Default model `large-v3-turbo` (~1.5 GB); handles mixed Chinese + English correctly.
- **Zero-friction setup** — first run auto-runs `install_mac.sh` / `install_linux.sh` if `ffmpeg` / `yt-dlp` / `whisper-cpp` / model is missing. No `sudo` required on Linux (user-mode venv only).
- **Bilibili-aware** — automatically tries browser cookies to bypass HTTP 412 risk control, falls back to anonymous fetch for public videos.
- **Clean output** — VTT tags stripped, HTML entities decoded, rolling/duplicate ASR fragments deduplicated, no leftover temp files.

## Quick Start

```bash
bash scripts/video_to_md.sh "<video-url>" [output-dir]
```

- `<video-url>`: any `youtube.com` / `youtu.be` / `bilibili.com` / `b23.tv` URL.
- `[output-dir]`: optional; defaults to current working directory.

`stdout` prints only the final `.md` path; progress and warnings go to `stderr`.

**First run on a clean machine just works** — the script self-checks dependencies and triggers the installer for your OS if anything is missing.

## Platform Support

| Platform | Acceleration | Prerequisites |
|---|---|---|
| macOS (Apple Silicon) | Metal GPU via `whisper.cpp` | Homebrew |
| Linux + NVIDIA GPU | CUDA via `faster-whisper` (pip wheel bundles CUDA runtime) | `python3` + NVIDIA driver (`nvidia-smi`). No CUDA toolkit / no `sudo` needed. |
| Linux CPU only | CPU fallback via `faster-whisper` | `python3`. Much slower; works without GPU. |
| Windows | Not supported | — |

## Output Format

Filename: `YYYY-MM-DD-<sanitized-title>.md`

```markdown
---
title: "Video title"
channel: "Channel / UP主"
url: "<original-url>"
video_id: "..."
upload_date: "YYYY-MM-DD"
duration: "MM:SS"
saved_at: "YYYY-MM-DD"
transcript_source: "subtitles" | "asr-whisper-cpp"
type: "video-transcript"
---

# Video title

> Source: channel · url

## 视频简介
(original description)

## 章节
- [MM:SS] Chapter name ...   ← only if the source provides chapters

## 转录正文

### [MM:SS] Chapter name
Continuous transcript text...
```

When no chapters are available (typical for Bilibili), text is segmented to ~400-char paragraphs with leading timestamps.

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `YT_MODEL` | `large-v3-turbo` | Whisper model name |
| `YT_LANG` | (auto-detect) | Force language e.g. `zh` / `en` |
| `YT_BROWSER` | `chrome` (Bilibili only) | Cookie source: `chrome` / `firefox` / `edge` / `brave` / `safari` / `none` |
| `FW_DEVICE` | `cuda` if available, else `cpu` | Force device for `faster-whisper` |
| `FW_COMPUTE` | (auto) | e.g. `int8` for low-mem CPU |
| `FW_MODEL` | `YT_MODEL` | Override model just for `faster-whisper` |
| `HF_ENDPOINT` | `https://hf-mirror.com` | HuggingFace download mirror |
| `VIDEO2MD_VENV` | `$HOME/.local/share/video2md/venv` | Linux venv path |

## Install as a Claude Code Skill

Clone the repo, then symlink it into your Claude Code skills directory:

```bash
git clone https://github.com/lily983/video2md.git
mkdir -p ~/.claude/skills
ln -s "$(pwd)/video2md" ~/.claude/skills/video2md
```

Restart `claude` — the skill becomes discoverable. Trigger phrases include "save this YouTube/Bilibili video", "转成 markdown", "做成附件" etc.

## Known Limitations

- **Bilibili HTTP 412**: if the script's Chrome-cookie + no-cookie fallback both fail, you typically need: (1) logged-in browser, (2) browser process killed (cookies DB unlocked), (3) on Linux, `secretstorage` installed in the venv (the installer does this by default).
- **Linux SOCKS proxy pollution**: `HTTPS_PROXY=socks5://...` set system-wide will break Bilibili and the HF model mirror. The script unsets all proxy vars and sets `NO_PROXY=*` before fetching; for YouTube from mainland China you need to re-enable an HTTP proxy and explicitly exclude `hf-mirror.com`, `bilibili.com`, etc. in `NO_PROXY`.
- **Blackwell GPUs (RTX 50 series)**: CUDA init may fail on older `ctranslate2` wheels. Script auto-falls back to CPU. Upgrade `ctranslate2` + `faster-whisper` for native GPU support.
- **`turbo` Chinese output** may mix Simplified / Traditional depending on content — post-process if you need uniformity.

See `SKILL.md` for the full operational checklist (proxy/cookie handling, edge cases, the agent-facing triggers).

## What it does NOT do

- No video/audio download retention (audio fetched only during transcription, deleted afterward).
- No frame extraction, no speaker diarization.
- No intermediate files in the output directory.

## License

[MIT](./LICENSE)
