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
| **OpenCode** | ❌ 官方明确不支持 | ⚠️ 装了但崩溃 | 有社区 Bionic 移植，但有未解决问题，见 10.3 |
| **Claude Code** | ❌ 不支持 | 社区有方案 | 需 Node.js，有非官方移植 |
| **Codex CLI** | ❌ 不支持 | 社区有方案 | 需 Node.js |
| **Hermes** | ❌ | 未充分调研 | — |
| **Cline / Roo** | ❌ | 需 VS Code | Termux 里跑 VS Code 困难 |
| **Aider** | ⚠️ 部分可行 | 需 Python | 纯 Python，理论上最容易移植 |

**共同规律**：主流 Agent 都是「Node.js 包 + 预编译原生二进制」，卡在原生二进制那一步。

---

## 10.3 OpenCode 部署实录（未完成）

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

## 10.4 推荐的技术路线

### 结论：优先选有官方/成熟 Termux 支持的

按可行性排序：

| 优先级 | 方案 | 理由 |
|--------|------|------|
| **1** | **Aider** | 纯 Python，`pkg install python && pip install aider-chat`，无原生二进制 |
| **2** | **官方支持 Termux 的 CLI 工具** | 无移植问题 |
| **3** | **OpenCode（serve 模式 + 自建客户端）** | API 已验证可用 |
| **4** | **Claude Code / Codex CLI 的社区移植** | 需验证，生态变化快 |
| **5** | **proot-distro + 完整发行版** | 最后手段，性能损失明显 |

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

## 10.5 验证清单

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

## 10.6 长时间运行 Agent 的注意事项

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

## 10.7 其他已确认的事实

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
