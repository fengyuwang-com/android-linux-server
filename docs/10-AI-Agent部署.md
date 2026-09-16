# 10 - 在手机上部署 AI Agent

**本章记录：哪些 AI 编码 Agent 能在无 root 的 Android/Termux 上跑，以及踩过的坑。**

---

## 10.1 核心障碍：Bionic vs glibc

这是理解一切问题的前提。

| | 标准 Linux | Android / Termux |
|---|---|---|
| **C 库** | glibc | **Bionic** |
| **动态链接器** | `/lib/ld-linux-aarch64.so.1` | `/system/bin/linker64` |
| **可执行文件要求** | 普通 ELF | **必须 PIE**（Android 5.0+ 强制） |

### 后果

绝大多数为 Linux 预编译的二进制**在 Termux 上跑不了**：

```bash
$ ./some-linux-binary
bash: ./some-linux-binary: cannot execute: required file not found
```

这个错误**具有误导性**——不是文件不存在，是它要求的动态链接器不存在。

即使手动改链接器也不行：

```bash
$ patchelf --set-interpreter /system/bin/linker64 ./binary
$ ./binary
bash: ./binary: cannot execute: required file not found   # 因为不是 PIE
```

### 三种解法

| 方案 | 思路 | 代价 |
|------|------|------|
| **A. 用有 Termux 移植版的工具** | 社区已重编译 | 无 |
| **B. proot-distro 跑完整发行版** | 在容器里跑 glibc | 性能损失、内存翻倍 |
| **C. 从源码自己编** | 针对 Bionic 编译 | 费时，依赖复杂 |

---

## 10.2 各 Agent 的实测状态

### ⚠️ 准确性声明

下表基于 **2026-09 实测 + 社区资料**。AI Agent 生态变化极快，**请自行验证**。

| Agent | 官方支持 Android | 当前状态 | 说明 |
|-------|-----------------|---------|------|
| **Hermes** | ✅ **有官方 Termux 文档** | ✅ **推荐首选** | 见 10.8 |
| **Claude Code** | ❌ 不支持 | ✅ 实测能跑 | 经 `glibc-runner` 跑通，见 10.4 |
| **OpenCode** | ❌ 官方明确不支持 | ⚠️ 装了但崩溃 | 社区 Bionic 移植，未解决，见 10.7 |
| **Codex CLI** | ❌ 不支持 | 社区有方案 | 需 Node.js |
| **Cline / Roo** | ❌ | 需 VS Code | Termux 里跑 VS Code 困难 |
| **Aider** | ⚠️ 部分可行 | 需 Python | 纯 Python，理论上最容易移植 |

**共同规律**：主流 Agent 都是「Node.js 包 + 预编译原生二进制」，卡在原生二进制那一步。

**唯一的例外是 Hermes**：它是纯 Python 项目，官方专门维护了 `constraints-termux.txt` 和 `.[termux]` 安装组，并且官方文档里就有 Termux 安装章节。这是目前唯一一个**厂商亲自保证 Android 可用**的编码 Agent。

---

## 10.3 三种绕开 Bionic 限制的手段

从上表可以看出，能跑起来的方案全都绕开了「预编译 glibc 二进制」这个死结：

| 手段 | 适用条件 | 代表 |
|------|---------|------|
| **A. 纯解释型语言** | 项目本身没原生二进制 | **Hermes**（纯 Python）、Aider |
| **B. 官方发 linux-arm64 PIE 二进制 + glibc-runner** | 厂商发了 ARM64 版且是 PIE | **Claude Code** |
| **C. 社区 Bionic 移植** | 有人愿意做 | OpenCode（有 bug 未解） |
| D. proot-distro 完整发行版 | 兜底 | 见 10.8 |

**优先尝试 A，其次 B。** C 依赖社区维护，随时可能失修；D 有性能损失。

---

## 10.4 Claude Code 部署（已跑通，这是关键突破）

**Claude Code 是第一个在无 root 的 Termux 里真正跑起来的商业 Agent。**

### 方案：glibc-runner + 官方 ARM64 二进制

不需要 proot，不需要重新编译，**直接用 Anthropic 官方的 linux-arm64 二进制**。

原理：`glibc-runner`（Termux 官方仓库的包）在 Termux 里提供一个 glibc 动态链接器：

```
$PREFIX/glibc/lib/ld-linux-aarch64.so.1
```

然后用 `patchelf` 把二进制的 ELF interpreter 字段指过去，内核就能直接 exec 它，**没有 proot 的性能损失**。

### 安装

```bash
pkg install -y glibc-runner patchelf

# 用社区的一键脚本（封装了 patchelf + 依赖处理）
git clone https://github.com/gtbuchanan/claude-code-termux.git
cd claude-code-termux
./install.sh
```

### 实测结果

```bash
$ claude --version
2.1.273          # ✅

$ claude --help
# ✅ 完整命令集正常输出
```

**这证明了 glibc-runner 路线的普适性**——凡是官方发 linux-arm64 二进制（PIE 编译）的工具，都能用这个方法跑起来。

### ❌ 遗留问题：认证

```bash
$ claude
Not logged in · Please run /login
```

没有 Anthropic 账号，所以需要走第三方网关。踩到的坑见 10.5。

---

## 10.5 第三方网关：协议转换才是真问题

**背景**：用户没有 Anthropic 账号（"这狗日的公司，他妈老是封号"），需要用聚合 API 替代。

国内常用 **CC Switch** 管理这类配置。它的数据库在：

```
C:\Users\a8881\.cc-switch\cc-switch.db     # SQLite
```

provider 存在 `providers` 表的 `settings_config` JSON 里，`env` 字段就是一组环境变量。

### 误区一：CC Switch 不一定在路由

查库发现 claude 的代理是**关着的**：

```
proxy_enabled = 0
enabled = 0
```

也就是说它**只注入环境变量，不做协议转换**。这个区别是决定性的：

| 模式 | 行为 | 能否解决协议差异 |
|------|------|-----------------|
| 代理关闭 | 只写 `env` 变量 | ❌ 不能 |
| 代理开启 (`127.0.0.1:15721`) | 真的转发并转换 | ✅ 能 |

### 误区二：环境变量不能解决协议不同

Claude Code 说的是 **Anthropic Messages API**（`POST /v1/messages`）。

而绝大多数聚合网关给的是 **OpenAI Chat Completions**（`POST /v1/chat/completions`）。

**这是两套请求/响应格式，光改 `ANTHROPIC_BASE_URL` 是不够的。**

```bash
# 手机上部署的 ~/.claude-env（未验证成功）
export ANTHROPIC_BASE_URL="https://opencode.ai/zen/go/v1"
export ANTHROPIC_AUTH_TOKEN="sk-..."
export ANTHROPIC_MODEL="claude-sonnet-5"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-haiku-4-5-20251001"
export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-5"
export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-4-8"
```

### 未解决的模型映射

两个问题都没验证：

1. **端点是否真的同时暴露 `/v1/messages`**
   - 如果只提供 `/v1/chat/completions`，Claude Code 直接不通
   - 测试两个端点都返回 `HTTP 401`，**结论不成立**（401 是认证失败，不是 404，说明不了问题）

2. **模型名映射是否成立**
   - `claude-sonnet-5` / `claude-opus-4-8` 这些名字是网关自己编的
   - 需要确认网关认不认，以及真实的模型 ID 是什么

### 正确的解法

**协议转换必须在中间层做**，两个方向：

| 方案 | 做法 |
|------|------|
| **A. 开 CC Switch 的代理模式** | 让它 `127.0.0.1:15721` 真转发并转换协议 |
| **B. 用本来就支持多协议的 Agent** | **← 这就是 Hermes 的价值，见 10.6** |

---

## 10.6 Hermes：目前最适合手机的编码 Agent

**结论先行：如果要一个"会写代码、手机上能跑、能接 DeepSeek"的 Agent，Hermes 是当前最优解。**

### 为什么是它

| 维度 | Hermes | Claude Code | OpenCode |
|------|--------|-------------|----------|
| **官方 Termux 支持** | ✅ 有专门文档和约束文件 | ❌ | ❌（明确 not planned） |
| **运行方式** | 纯 Python，无原生二进制 | glibc 二进制 + glibc-runner | Bionic 移植（有 bug） |
| **自定义端点** | ✅ **原生支持**，配置项一级公民 | ❌ 只能改 base_url，协议仍是 Anthropic | ✅ |
| **DeepSeek** | ✅ 官方文档点名支持 | ❌ 需网关转换 | ✅ |
| **编码能力** | 好，但不是最强 | **最强** | 好 |

### 安装（官方文档路径）

官方文档：https://hermes-agent.nousresearch.com/docs/getting-started/termux

```bash
# 1. 基础依赖
pkg update
pkg install -y git python clang rust make pkg-config libffi openssl nodejs ripgrep ffmpeg

# 2. ⚠️ Python 版本是最大的坑
# Hermes 要求 >=3.11,<3.14，但 Termux 官方源现在是 3.14.x，超范围了
pkg install -y tur-repo
pkg install -y python3.13
# 以下所有 python 命令都要换成 python3.13

# 3. 克隆
git clone https://github.com/NousResearch/hermes-agent.git
cd hermes-agent

# 4. 虚拟环境
python3.13 -m venv venv
source venv/bin/activate

# ⚠️ 这行对 Rust/maturin 系的包（如 jiter）是必须的
export ANDROID_API_LEVEL="$(getprop ro.build.version.sdk)"

python -m pip install --upgrade pip setuptools wheel

# 5. 装 Termux 专用依赖组（不要用 .[all]，会挂）
python -m pip install -e '.[termux]' -c constraints-termux.txt

# 6. 放上 PATH
ln -sf "$PWD/venv/bin/hermes" "$PREFIX/bin/hermes"

# 7. 验证
hermes --version
hermes doctor

# 8. 配置模型
hermes model      # 或直接写 ~/.hermes/.env
hermes setup      # 交互式向导
```

### 已知坑（官方文档明说的）

| 坑 | 原因 | 解法 |
|----|------|------|
| `.[all]` 装不上 | `voice` extra 拉 `faster-whisper` → `ctranslate2`，**没有 Android wheel** | 改用 `.[termux]` |
| `uv pip install` 失败 | uv 在 Android 上行为异常 | 用标准库 `venv` + `pip` |
| Python 版本不符 | Termux 给了 3.14，超出 `<3.14` 范围 | `tur-repo` 装 `python3.13` |
| Rust 包编译失败 | 缺 `ANDROID_API_LEVEL` | `export ANDROID_API_LEVEL="$(getprop ro.build.version.sdk)"` |

### 接自定义端点（解决 Claude Code 的死结）

Hermes 的配置里 `base_url` 是**一等公民**：

```yaml
# ~/.hermes/config.yaml
providers:
  deepseek:
    base_url: https://api.deepseek.com/v1     # 或任何 OpenAI 兼容端点
    api_key: ${DEEPSEEK_API_KEY}
    models:
      deepseek-chat:
        timeout_seconds: 600
```

或者交互式配置：

```bash
hermes setup
# 选 "Custom OpenAI-compatible endpoint"
# Base URL 填到 /v1 结尾（Hermes 自己会拼 /chat/completions）
# 填 API key
```

也支持环境变量引用，写 `${VAR_NAME}` 即可：

```yaml
api_key: ${DEEPSEEK_API_KEY}
```

**关键点**：Hermes 说 **OpenAI wire protocol**，而 DeepSeek 也说 OpenAI 协议，**两者天然对得上，不需要任何转换层**。这正是 Claude Code 卡住的地方。

官方点名的 200+ 模型包含：OpenAI、Anthropic、Gemini、**DeepSeek**、Qwen、GLM、Ollama 本地模型。

### 能力上的诚实评价

综合多个第三方横评：

- **编码硬实力**：Hermes **不如** Claude Code。有测评跑了 18 个任务，Hermes 赢 14 个，但**输掉的 4 个全是"代码硬功夫"类**。
- **它赢的地方**：跨会话持久记忆（SQLite + FTS5 全文索引，能记住上周五在查的 bug）、自建技能、更广的自动化。
- **一句话**：想"仓库里高强度改代码"，Claude Code 更强；想"长期陪着干活的 Agent"，Hermes 更强。

> 对手机场景来说，**能跑起来 > 理论最强**。Claude Code 编码更强但认证走不通，Hermes 编码稍弱但开箱即用、协议天然兼容。

### 备选：一键安装脚本（第三方，用 proot）

社区有个傻瓜脚本，走 proot-distro + Ubuntu 路线：

```bash
curl -fsSL https://raw.githubusercontent.com/AbuZar-Ansarii/Hermes-Agent-On-Android/main/nous_agent.sh | bash
```

**优点**：不用管 Python 版本、依赖编译，一步到位。
**缺点**：proot 有性能损失和内存翻倍（见 10.10），**能走官方原生路径就别用这个**。

系统要求（该脚本给出的参考值）：Android 11+（推荐 13/14/15）、存储 3GB（推荐 5GB+）、RAM 2GB（推荐 4GB+）。

---

## 10.7 OpenCode 部署实录（未完成）

**这部分是完整的排查过程，供未来继续。**

### 背景

OpenCode（`anomalyco/opencode`，原 `sst/opencode`）是开源的终端 AI 编码 Agent，MIT 许可，模型无关。

### 官方立场：不支持 Android

官方 issue [#10504](https://github.com/anomalyco/opencode/issues/10504) 明确记录了在 Termux 上无法运行，**被关闭为 "not planned"（不打算修）**。

两个硬伤：

1. 二进制要求 glibc 动态链接器 `/lib/ld-linux-aarch64.so.1`（Android 没有）
2. 即使改链接器也不行——**不是 PIE 编译**

### 社区方案：opencode-bionic

`bd-loser/opencode-bionic` 做了完整移植，包含三部分工作：

| 组件 | 工作内容 |
|------|---------|
| **Bun 运行时** | 打补丁使其跑在 Bionic 上（TinyCC JIT、seccomp-trap 绕过、shebang 重映射） |
| **opentui 原生库** | 把 Zig 写的 TUI 库重编为 `android-arm64`，16KiB 页对齐 |
| **opencode 补丁** | 把 `@opentui/*` 替换为 `@androidtui/*` |

### 安装（这部分成功了）

```bash
curl -fsSL https://raw.githubusercontent.com/bd-loser/opencode-bionic/main/install.sh -o ~/oc-install.sh
bash ~/oc-install.sh
```

**结果**：✅ 安装成功，版本 1.18.31，SHA256 校验通过。

```bash
$ opencode --version
1.18.31
```

### ✅ 能正常工作的部分

```bash
opencode --help          # 完整命令集
opencode debug info      # 环境探测
opencode debug skill     # 技能加载
opencode providers list  # provider 管理
opencode serve           # HTTP 服务器 ← 完全正常
```

`opencode serve` 启动成功：

```
opencode server listening on http://127.0.0.1:4096
```

HTTP API 也正常：

```bash
$ curl -s http://127.0.0.1:4096/session
[{"id":"ses_...","slug":"hidden-moon","model":{"id":"big-pickle","providerID":"opencode"}}]

$ curl -s http://127.0.0.1:4096/app
<!doctype html><html>... OpenCode 网页界面 HTML ...
```

### ❌ 未解决的问题：`opencode run` 崩溃

**症状**：任何实际对话都失败。

```bash
$ opencode run "say OK"
Error: {
  "name": "UnknownError",
  "data": { "message": "Unexpected server error..." }
}
```

**错误栈**（关键线索）：

```
TypeError: undefined is not an object (evaluating 'a.name')
    at resolve (/$bunfs/root/chunk-cc8ps5vb.js:2:1659)
    at a (chunk-cc8ps5vb.js:2:936)
    at map (native:1:11)
    at SystemPrompt.environment (chunk-8fg5vk9e.js:50:13096)
    at SessionPrompt.run (...)
```

**日志**：
```
level=INFO  message=stream providerID=opencode modelID=big-pickle small=true agent=title mode=primary
level=ERROR message=failed error="TypeError: undefined is not an object (evaluating 'a.name')"
level=WARN  message="background dependency install failed" error="ReleaseError: metadata missing"
```

### 已排除的原因

| 排查项 | 结果 |
|--------|------|
| 是否在 git 仓库 | ❌ 不是原因（git 仓库里同样崩） |
| 空目录 vs 有文件 | ❌ 不是原因（都崩） |
| `TERM=dumb` | ⚠️ 影响 `terminal: unknown`，但设了 `TERM=xterm-256color` 仍崩 |
| 缺 `/etc/os-release` | ❌ 不是原因（造了一个仍崩） |
| **ripgrep 平台不支持** | ✅ **找到一个真实问题并修复了**（见下） |
| 缺 Node.js/npm | ❌ 装了仍崩 |
| 缺用户名/时区/日期 | ❌ 都正常 |
| 权限规则配置 | ❌ agent 配置正常解析 |

### 已修复的部分

**问题**：内嵌的 ripgrep 没有 Android 版本。

```bash
$ opencode debug rg files
Error: unsupported platform for ripgrep: arm64-android
```

**修复**：装 Termux 原生 ripgrep。

```bash
pkg install -y ripgrep
```

修复后：

```bash
$ opencode debug rg files
a.txt                          # ✅ 正常了
```

**但 `opencode run` 仍然崩溃**，说明还有第二处问题。

### 剩余线索与下一步方向

1. **崩溃点在 `SystemPrompt.environment` 的递归 `resolve()`**
   - 两层嵌套 `map` 结构，说明在处理"列表里的列表"
   - 某个对象为 undefined，然后取 `.name` 抛错

2. **`background dependency install failed: ReleaseError: metadata missing`**
   - 发生在 `~/.opencode/` 目录（OpenCode 自动创建的项目级目录）
   - 它在尝试自动安装依赖，但元数据缺失
   - 怀疑点：这个自动依赖安装逻辑在 Bionic 上行为异常

3. **`os: Linux 6.6.56-android15 arm64` + `terminal: unknown`**
   - 平台字符串是 `arm64-android`，某些查表可能没有这个 key

4. **建议的下一步**
   - 逆向 `chunk-cc8ps5vb.js` 的 `resolve()` 函数（Bun 内嵌虚拟路径 `/$bunfs/root/`，需从 ELF 提取）
   - 或在上游仓库提交 issue 寻求帮助
   - 或改试 `opencode serve` + HTTP API 的路径（**API 是好的，只有 TUI 路径崩**）

> **重要发现**：`opencode serve` 和 HTTP API **完全正常**。
> 这意味着核心引擎没问题，问题只在 `run` 这条走 TUI/系统提示词渲染的路径上。
> **可行的绕行方案**：用 `serve` 模式 + 自己写客户端调 API，绕过 TUI。

---

## 10.8 推荐的技术路线

### 结论：按"能否原生跑 + 能否接自定义端点"排序

| 优先级 | 方案 | 理由 |
|--------|------|------|
| **1** | **Hermes** | ✅ 官方 Termux 文档 + ✅ 原生自定义端点，两个坑都绕开了 |
| **2** | **Aider** | 纯 Python，`pkg install python && pip install aider-chat`，无原生二进制；且原生支持自定义端点 |
| **3** | **Claude Code + glibc-runner** | ✅ 已实测跑通，但**认证/协议转换未解决**，需要网关支持 `/v1/messages` |
| **4** | **OpenCode（serve 模式 + 自建客户端）** | API 已验证可用，绕开崩溃的 `run` 路径 |
| **5** | **proot-distro + 完整发行版** | 最后手段，性能损失明显 |

### 决策树

```
要"手机上能用的编码 Agent"
│
├─ 有 Anthropic 官方账号？
│   └─ 有 → Claude Code（glibc-runner，已跑通，编码最强）
│
└─ 没有，要用第三方 API / DeepSeek？
    └─ 用 Hermes（原生 OpenAI 协议，不用转换层）
```

### 关于 proot-distro

如果非要跑 glibc 程序：

```bash
pkg install -y proot-distro
proot-distro install debian
proot-distro login debian
# 在 Debian 里正常装任何东西
```

**代价**：
- 内存占用翻倍（要加载完整的 glibc 环境）
- 性能损失（无硬件虚拟化，纯用户态模拟）
- 文件路径映射复杂
- 后台保活更难

**建议**：除非别无选择，否则别用。

---

## 10.9 验证清单

部署任何 Agent 前，先确认这些基础条件：

```bash
# 1. 架构与 libc
uname -m                # aarch64
ls -la /system/bin/linker64   # Bionic 链接器存在

# 2. Node.js（如果需要）
node --version
npm --version

# 3. Python（如果需要）
python --version
pip --version

# 4. ripgrep（很多 Agent 依赖）
rg --version

# 5. 空间（Agent 通常几百 MB）
df -h $HOME

# 6. 息屏保活（长时间跑必须）
pgrep -af termux-media-player
```

---

## 10.10 长时间运行 Agent 的注意事项

| 问题 | 解法 |
|------|------|
| 息屏被杀 | 必须开音频保活（见 [05-息屏保活.md](05-息屏保活.md)） |
| 内存不足 | 手机 14GB 够用，但 Agent + 桌面同时跑会挤 |
| 网络中断 | 用 `tmux` 或 `screen` 保持会话 |
| API 超时 | 移动网络延迟高，调大超时 |
| 电量 | 持续跑会明显耗电，建议插着充电 |

### 用 tmux 保持会话

```bash
pkg install -y tmux

tmux new -s agent      # 新建会话
# ... 跑 Agent ...
# Ctrl+B, D 脱离

tmux attach -t agent   # 重新连上
```

---

## 10.11 其他已确认的事实

### Microsoft Edge / Chrome 装不了

同 10.1 的架构问题。Termux 有官方重编译的 **Firefox** 和 **Chromium**：

```bash
pkg install -y firefox    # 155.0.1，实测可用
pkg install -y chromium
```

### Termux 里 npm 全局包的位置

```
$PREFIX/lib/node_modules
```

### 安装体积参考

| 软件 | 大小 |
|------|------|
| OpenCode（含 Bun 运行时） | 141 MB |
| Node.js + npm | ~100 MB |
| Firefox | 270 MB（安装后） |
| XFCE4 桌面 | ~500 MB |

---

## 下一步

回到 [README.md](../README.md) 查看总览。
