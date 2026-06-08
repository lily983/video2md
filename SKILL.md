---
name: video2md
description: Video2MD — 跨平台(macOS Apple Silicon / Linux)把 YouTube 或哔哩哔哩(Bilibili)视频转成单个 Markdown 文档,供作为模型对话的附件/参考材料。核心是一个脚本 video_to_md.sh:用户给出视频链接(youtube.com / youtu.be / bilibili.com / b23.tv)并希望"保存""转成文档""生成 md""存下来喂给模型""做成材料/附件"时直接跑它——有字幕用字幕,没字幕用 whisper.cpp 本地转录(macOS 走 Metal GPU;Linux 有 CUDA 工具链则走 NVIDIA GPU,否则 CPU);**缺 ffmpeg/yt-dlp/whisper-cpp 或模型时会按系统自动调用 install_mac.sh / install_linux.sh 装好,无需手动预装**。默认模型 large-v3-turbo,中英混说也能正确混排。B 站链接会自动带浏览器 cookie 绕过风控。也适用于英文表述:"save this YouTube/Bilibili video", "turn this video into a doc/markdown/transcript", "install video transcription tools"。本 Skill 面向在用户本机(macOS 或 Linux)运行的 agent(如本机 Claude Code);云端沙盒 agent 装的东西用户看不见,不应触发。

---

# Video2MD — 视频 → Markdown (跨平台)

把 **YouTube 或哔哩哔哩**视频转成单个 `.md` 文档(YAML 元信息头 + 简介 + 章节 + 清洗去重后的转录)。**有字幕用字幕,无字幕用 whisper.cpp 本地转录**。

**平台与加速**:
- **macOS (Apple Silicon)**:whisper.cpp + **Metal**(GPU),通过 Homebrew 安装,无需编译。
- **Linux**:**faster-whisper**(pip 装进用户态 venv,自带预编译 CUDA wheel,**只依赖 NVIDIA 驱动,无需 sudo / CUDA toolkit / 编译**)。有 N 卡走 GPU(`device=cuda`),否则走 CPU;CUDA 初始化失败自动回退 CPU。音频解码用其自带的 PyAV,无需系统 ffmpeg。
- 脚本按 `uname` 自动分流,使用者不用关心。

## 适用边界

**适用**:agent 运行在用户本机(macOS Apple Silicon,或带包管理器的 Linux),能调用本机命令行。支持平台 YouTube / 哔哩哔哩(底层 yt-dlp,其它站点多半也能跑但未验证)。

**不适用**:云端沙盒 agent(装的东西用户机器上看不到);Windows(未支持)。

## 主流程:转录(用户给链接时)

**触发**:用户给出 YouTube 或 B 站视频链接,想转成文档/保存/做材料/生成 md。

**前置**:
- macOS:仅需 Homebrew。
- Linux:仅需 `python3` + NVIDIA 驱动(`nvidia-smi` 能跑即可),**不需要 sudo、不需要 CUDA toolkit、不需要编译**。CUDA 运行库由 faster-whisper 的 pip wheel 自带。
脚本会自检依赖,缺啥自动装(Linux 首次会建 venv、pip 装 faster-whisper/yt-dlp、下模型,几分钟)。

**步骤**:

1. 取链接。
2. **调用前置(关键,几乎每次都要做)**:
   - **第一步:关闭浏览器**(任何平台,任何链接,如果脚本可能读 cookie):
     ```bash
     pkill -i chrome; sleep 3; pgrep -c chrome  # 必须输出 0
     ```
     **为什么先做**:cookie DB 被锁时,后面代理设置、yt-dlp 调用全都会拿不到登录态,导致 412/429。实测必须在设置代理**之前**先 kill。
   
   - **第二步:设置代理**(Linux + 中国大陆):
     - **B 站链接**:`unset HTTPS_PROXY HTTP_PROXY ALL_PROXY https_proxy http_proxy all_proxy && export NO_PROXY="*"` — SOCKS 代理污染必爆 412。
     - **YouTube 链接**:`export HTTPS_PROXY=http://127.0.0.1:7890; export HTTP_PROXY=$HTTPS_PROXY; export ALL_PROXY=$HTTPS_PROXY; export NO_PROXY="localhost,127.0.0.1,hf-mirror.com,huggingface.co,bilibili.com,bilivideo.com,b23.tv,bilivideo.cn"` — YouTube 必须走代理,NO_PROXY 排除 hf-mirror(模型下载)和 B 站域名。
3. 运行(第二个参数 = 输出目录):
   ```bash
   bash scripts/video_to_md.sh "<视频链接>" [输出目录]
   ```
   - **默认输出目录优先级**:用户当次指定 > 用户在 memory 里设的默认值 > 当前工作目录 `pwd`。**不要默认丢到 `/tmp/` 或 SKILL 目录里**。这台 Hermes 主机当前的用户默认是 `/home/xiaoli/Cybopal-wiki/_inbox/`(参见 memory)。
   - 首次跑会按系统自动安装依赖。
4. **stdout 只打印最终 `.md` 路径**,进度/告警走 stderr。从 stdout 拿路径。
5. 把 `.md` 呈现给用户(present_files 之类)。

**B 站特别说明**:B 站有风控,裸抓常报 `HTTP 412`。脚本检测到 B 站链接时**默认尝试 Chrome cookie** 绕过;**若该浏览器没装/没登录导致抓取失败,会自动改"无 cookie"重试**(公开视频常可成功)。
- 用别的已登录浏览器:`YT_BROWSER=firefox`(或 chrome/edge/brave/safari);**读哪个就先关掉它**。
- 明确不带 cookie(测公开视频/不登录):`YT_BROWSER=none`。
- macOS 上 Safari 需"完全磁盘访问权限"才能读 cookie,否则用 Chrome/Firefox;Linux 上若无图形浏览器,多用 `YT_BROWSER=none` 或指定 firefox。

**模型**:默认 `large-v3-turbo`(~1.5GB,质量速度甜点,中英混说能正确混排)。一般不用改;需要时 `YT_MODEL=large-v3 bash scripts/video_to_md.sh "<链接>"`。

**语言**:默认不预设,whisper 自动检测。仅在确需强制时设 `YT_LANG=zh` / `YT_LANG=en`。

**单独预装(可选)**:
- macOS:`bash scripts/install_mac.sh`
- Linux:`bash scripts/install_linux.sh`(建 venv + pip 装 + 下模型)。可选 `FW_MODEL=<受支持名或HF仓库>` 覆盖模型;`FW_DEVICE=cpu`/`FW_COMPUTE=int8` 强制 CPU/精度;`HF_ENDPOINT` 改下载镜像。

## 输出格式

文件名:`YYYY-MM-DD-<视频标题>.md`(标题已做文件名安全化)。

```markdown
---
title: "视频标题"
channel: "频道名 / UP主"
url: "<原始链接>"
video_id: "..."
upload_date: "YYYY-MM-DD"
duration: "MM:SS"
saved_at: "YYYY-MM-DD"
transcript_source: "subtitles" | "asr-whisper-cpp"
type: "video-transcript"
---

# 视频标题

> 来源:频道名 · 链接
> 该文档为上述视频的转录稿与元数据,供作为模型对话的参考材料。

> ⚠ 本视频无字幕,转录由本地 whisper.cpp 生成,可能存在识别误差。  ← 仅 ASR 路径

## 视频简介
(原简介,HTML 实体已解码)

## 章节
- [MM:SS] 章节名 ...   ← 仅当源站提供章节(YouTube 常有,B 站常无)

## 转录正文

### [MM:SS] 章节名
连贯转录文本(VTT 标签已剥,HTML 实体已解码,滚动/复读重复已去除)……
```

无章节时(B 站投稿通常如此)按约 400 字一段、段首带时间戳。

## 边界情况

- **缺依赖/模型**:`video_to_md.sh` 启动时自检并按系统自动跑 `install_mac.sh` / `install_linux.sh`。例外:macOS 没装 Homebrew、Linux 没装 python3——会提示后退出。
- **Linux Blackwell(如 RTX 50 系)兼容**:这类新卡(sm_120)需较新的 CUDA 运行库;pip 的 faster-whisper/CTranslate2 wheel 若版本够新可直接用,否则可能 CUDA 初始化失败——脚本会**自动回退 CPU**(慢)。遇到此情况升级 `pip install -U ctranslate2 faster-whisper` 或换更新的 wheel。
- **Linux 转录用 GPU 还是 CPU**:有 `nvidia-smi` 默认 `device=cuda`;想强制 CPU 用 `FW_DEVICE=cpu`。
- **B 站 HTTP 412**:脚本已自动带 Chrome cookie,失败会改无 cookie 自动重试。**仍 412** 时按下面三件事**全部**核查(实测三者缺一就 412):
  1. **该浏览器登录过 B 站** — `cookies-from-browser` 读到了 cookie 不等于读到登录态。判定方法:`yt-dlp --cookies-from-browser chrome --cookies /tmp/x.txt --skip-download <URL>`,然后 `grep -E "SESSDATA|bili_jct|DedeUserID" /tmp/x.txt`,三个一个都没有 = 没登录,让用户在该浏览器登录后重试。
  2. **关掉该浏览器进程** — Chrome 开着会锁 cookie DB,yt-dlp 报错 `database is locked` 或静默拿不到。`pgrep -c chrome` 必须为 0。
  3. **(Linux 专有)装了 `secretstorage`** — 不装的话 yt-dlp 解密 Chrome AES-CBC cookie 大批静默失败,日志里出现 `secretstorage not available` + `failed to decrypt cookie ... X could not be decrypted`,登录态 cookie 就在解密失败那批里。修法:`<venv>/bin/pip install secretstorage`。本 SKILL 的 install_linux.sh 已默认装,老版本装的需手动补。
     - **v11 cookie 解密失败不一定是致命问题**:即使看到 `cannot decrypt v11 cookies: no key found` + `1182 could not be decrypted`,yt-dlp 仍可能通过其他认证路径(session tokens、fallback auth)成功抓取。只有当最终抓取失败(412/429/403)时才需要排查 cookie 问题;v11 警告本身不阻塞成功。
- **(Linux 专有)SOCKS 代理污染**:用户机器若设了 `HTTPS_PROXY=socks5://...`(国内常见 Clash/V2Ray),会让 yt-dlp 把 B 站/hf-mirror 请求也送进代理,B 站直接拒、hf-mirror 还要求 httpx 装 `socksio` 否则崩溃。**脚本执行前 unset 全套代理变量并 `export NO_PROXY="*"`**:`unset HTTPS_PROXY HTTP_PROXY ALL_PROXY https_proxy http_proxy all_proxy`。B 站和 hf-mirror.com 本就在国内,直连最快。**YouTube 反过来**:在国内必须走代理(`export HTTPS_PROXY=http://127.0.0.1:7890` 等),`NO_PROXY` 要明确排除 `hf-mirror.com,huggingface.co,bilibili.com,bilivideo.com,b23.tv`,避免污染模型下载和 B 站。
- **YouTube 限流 429**:同样可加 `YT_BROWSER=<浏览器>` 用 cookie;先关该浏览器。Linux 上 cookie 解密同样需要 `secretstorage`(见上一条)。
- **显存/内存不足 OOM**:whisper 进程被 kill,脚本会出只有元数据的占位文档。退回默认 `large-v3-turbo` 或更小模型。
- **视频有字幕**:走字幕路径,秒级完成,不进入 whisper.cpp。
- **模型下载慢**:默认走 `hf-mirror.com`;可 `HF_MIRROR=https://huggingface.co ...` 改回 HF。
- **Metal 资源路径(仅 macOS)**:脚本自动设 `GGML_METAL_PATH_RESOURCES`,不用改 shell 配置。
- **B 站多 P**:默认只取主分 P。

## 性能预期(粗略)

- macOS M2 / Linux + NVIDIA GPU,`large-v3-turbo`:约为音频时长的 1/5~1/3(6 分钟视频约 1 分钟,55 分钟约 10 分钟)。
- Linux **纯 CPU**:慢很多(可能数倍于音频时长),仅作没有 GPU / CUDA 不兼容时的兜底。
- 首次跑多一段后端/模型初始化;Linux 首次还要建 venv + pip 安装(几分钟)。
- turbo 中文输出可能繁体或简体(随内容),需统一时自行后处理。

## 不做的事

- 不下载视频/音频本体(只取字幕与元数据;转录时下音频但用完即删)。
- 不抽取画面帧。
- 不做说话人分离。
- 不在输出目录留任何中间文件(临时目录用完即删,只剩 `.md`)。
