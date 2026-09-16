# Android Linux Server

把一台闲置 Android 手机，在**不 root** 的前提下改造成可远程 SSH 操作、带图形桌面的 Linux 服务器。

本仓库记录一套**已实测跑通**的完整方案，以及过程中踩过的所有坑。照着做可以完整复现。

> 实测设备：努比亚 M153 (P0110) / Android 16 / 8 核 ARM64 / 14GB RAM / 459GB 存储

---

## 这套方案能做什么

| 能力 | 说明 |
|------|------|
| **SSH 远程操作** | 电脑命令行直接进手机 Linux 环境 |
| **图形桌面** | XFCE4 + VNC，电脑上看到完整桌面 |
| **息屏不断连** | 手机锁屏后 SSH 依然存活（核心难点，见下） |
| **自愈机制** | 4 层冗余，进程被杀后 5 秒内自动恢复 |
| **跑脚本/定时任务** | Python、cron、完整 Linux 工具链 |
| **调用手机硬件** | 通知栏推送、剪贴板、震动、定位 |

**不需要 root。** 避开变砖、丢保修、银行 App 检测等风险。

---

## 快速开始

```bash
# 1. 进手机
ssh nubia

# 2. 开图形桌面
ssh nubia '~/start-vnc.sh'

# 3. 电脑上看桌面
vncviewer -passwd ~/.vnc/passwd <PHONE_IP>:5901
```

### 日常只记一个命令：`dt`

打开 Termux 时桌面会**自动启动**并打印连接地址。想控制就用：

```bash
dt          # 看状态（含连接地址）
dt on       # 开
dt off      # 关
```

---

## 文档

| 文档 | 内容 |
|------|------|
| [docs/01-准备工作.md](docs/01-准备工作.md) | Termux 选型、为什么必须装 Termux:API、Tailscale 组网 |
| [docs/02-SSH连接.md](docs/02-SSH连接.md) | sshd 配置、密钥免密登录 |
| [docs/03-工具链与镜像源.md](docs/03-工具链与镜像源.md) | 换清华源（默认源国内完全不通）、libc++ 版本坑 |
| [docs/04-图形桌面.md](docs/04-图形桌面.md) | XFCE4 + TigerVNC 完整配置 |
| [docs/05-息屏保活.md](docs/05-息屏保活.md) | **核心难点**：音频焦点方案骗过 Android 冻结机制 |
| [docs/06-ADB指南.md](docs/06-ADB指南.md) | ADB 配置、救援流程、系统级权限 |
| [docs/07-自愈机制.md](docs/07-自愈机制.md) | 4 层冗余保障 + dpkg 钩子 |
| [docs/08-故障排查.md](docs/08-故障排查.md) | 所有已知问题的症状与解法 |
| [docs/09-无root能力边界.md](docs/09-无root能力边界.md) | 能做什么、不能做什么、Shizuku 补充 |
| [docs/10-AI-Agent部署.md](docs/10-AI-Agent部署.md) | 在手机上跑 AI 编码 Agent：Bionic vs glibc、Claude Code 实测跑通、**Hermes 推荐方案**、第三方网关协议转换坑 |

---

## AI Agent 结论速览

手机（无 root Termux）上跑 AI 编码 Agent，**推荐 Hermes**：

| Agent | 能装吗 | 能接 DeepSeek 吗 | 评价 |
|-------|--------|-----------------|------|
| **Hermes** | ✅ 官方 Termux 文档 | ✅ 原生支持 | **首选**，纯 Python，协议天然兼容 |
| **Claude Code** | ✅ 已实测跑通 | ❌ 需协议转换 | 编码最强，但认证走不通 |
| **OpenCode** | ⚠️ 能装，`run` 崩溃 | ✅ | `serve` 模式可用 |
| **Aider** | ✅ 纯 Python | ✅ | 轻量备选 |

**核心洞察**：Claude Code 说 Anthropic 协议，DeepSeek 说 OpenAI 协议，**光改 base_url 不够，必须有转换层**。Hermes 原生说 OpenAI 协议，直接对上，不折腾。

详见 [docs/10-AI-Agent部署.md](docs/10-AI-Agent部署.md)

---

## 三个核心问题

这套方案的价值主要在于解决了三个**非显然**的问题：

### 1. 软件源国内不可达

Termux 默认镜像 `mirror.accum.se` 在瑞典，国内**完全连不上**（超时 30 秒）。

**迷惑性症状**：`pkg install` 卡死不动，但 `pkg update` 显示 "Hit" —— 那是读本地缓存，不是真连上了。

**解法**：换清华源，实测 0.58s（官方 CDN 9s，瑞典源超时）。
详见 [docs/03-工具链与镜像源.md](docs/03-工具链与镜像源.md)

### 2. 息屏即断连

Android 会把息屏后的后台应用移入**冻结组**，暂停 CPU 调度，`sshd` 随之失效。实测**连 20 秒都撑不过**。

`termux-wake-lock` 挡不住——它只防 CPU 休眠，防不住进程冻结策略。

**解法（音频焦点"免死金牌"）**：Android 对"正在播放音频"的应用有豁免权（认为它在执行用户可感知任务）。循环播放一个静音 AMR 文件即可骗过系统，实测息屏 7 分钟不断。
详见 [docs/05-息屏保活.md](docs/05-息屏保活.md)

**代价**：持续耗电。这是无 root 方案下的必要代价。

### 3. 装包会打死 sshd

`pkg upgrade` 替换 sshd 二进制时，会把**当前 SSH 会话连同进程一起打死**，而 cron 看门狗也同时被杀，无法自愈。

**解法**：装 apt 后置钩子，每次 dpkg 操作后自动拉起 sshd。
详见 [docs/07-自愈机制.md](docs/07-自愈机制.md)

---

## 自愈机制的 4 层设计

单机制都不可靠（`runsvdir` 会随 Termux 主进程被杀而消失），所以做了多层兜底：

| 层 | 机制 | 触发场景 | 实测恢复 |
|----|------|---------|---------|
| 1 | `runsvdir` 进程守护 | sshd 被单独杀掉 | 5 秒 |
| 2 | cron 看门狗 | runsvdir 也没了 | 60 秒内 |
| 3 | `.bashrc` 自启 | Termux 被 force-stop 后重开 | 5 秒 |
| 4 | Termux:Boot | 手机重启 | 开机后 |
| + | **apt dpkg 钩子** | `pkg upgrade` 打死 sshd | 装包结束时 |

一层失效，其他层兜底。

---

## 无 root 的边界

**能做**：跑脚本、定时任务、小型服务器、数据抓取、图形界面、调用手机硬件（通知/剪贴板/定位）、SSH 跳板。

**不能做**：模拟点击其他 App、读微信聊天记录、改系统设置、访问其他应用沙盒目录。

> 需要更强的自动化（如控制其他 App）可以装 **Shizuku** —— 通过 ADB 激活，不需要 root，能授予部分系统级 API 权限。

详见 [docs/09-无root能力边界.md](docs/09-无root能力边界.md)

---

## 脚本

`scripts/` 目录下是可复用的脚本：

| 脚本 | 作用 |
|------|------|
| **`dt.sh`** | **桌面一键开关：`dt on` / `dt off` / `dt status`** |
| `keepalive.sh` | 音频焦点保活 |
| `watchdog.sh` | cron 看门狗（守护 sshd/保活/VNC） |
| `start-vnc.sh` / `stop-vnc.sh` | 图形桌面启停（`dt` 的底层脚本） |
| `setup-sshd-hook.sh` | 安装 dpkg 后置钩子 |
| `rescue-via-adb.sh` | SSH 断了时用 ADB 救援 |

---

## 参考来源

- [通过 SSH 远程控制你的 Android 手机 — Termux 完整指南](https://blog.shirorikka.dpdns.org/posts/通过ssh远程控制你的android手机-termux完整指南/)
- [Termux SSH 锁屏断开详解：为什么 MIUI 会杀掉 untrusted_app 进程](https://www.cnblogs.com/zjw-blog/p/19410463)
- [驯服 HyperOS 3：Android 16 下 Termux SSH 永不断连的极简方案](https://www.cnblogs.com/zjw-blog/p/19433176)
- [如何用 VNC 遠端連線至 Termux 的 Linux 桌面](https://ivonblog.com/posts/vncserver-termux/)
- [Hermes Agent 官方 Termux 文档](https://hermes-agent.nousresearch.com/docs/getting-started/termux)
- [Hermes Agent 官方配置文档](https://hermes-agent.nousresearch.com/docs/user-guide/configuration)

---

## License

MIT
