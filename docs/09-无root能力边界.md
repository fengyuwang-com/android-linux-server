# 09 - 无 root 能力边界

## 9.1 ✅ 能做的

| 用途 | 说明 | 依赖 |
|------|------|------|
| **跑定时任务** | cron 已装，配合 `termux-notification` 推到通知栏 | cronie |
| **当小型服务器** | 跑 HTTP 服务，Tailscale 让所有设备可访问 | — |
| **数据抓取** | Python + requests，定时采集 | python |
| **文件/媒体处理** | ffmpeg 转码、压缩、提取 | ffmpeg |
| **远程开发环境** | 完整 Linux 工具链，clang 可编译原生程序 | clang |
| **图形界面** | XFCE 桌面已跑通，可装 GUI 软件 | x11-repo |
| **调用手机硬件** | 通知、剪贴板、震动、定位、短信读取 | Termux:API |
| **SSH 跳板** | 手机主动连出去，当代理 | openssh |
| **跑 AI Agent** | Node/Python 都能装（见 [10-AI-Agent部署.md](10-AI-Agent部署.md)） | — |

### Termux:API 能调用的硬件

```bash
termux-notification --title "标题" --content "内容"   # 通知栏
termux-clipboard-get / termux-clipboard-set           # 剪贴板
termux-vibrate -d 500                                 # 震动
termux-location                                       # 定位
termux-battery-status                                 # 电池
termux-sms-list -l 5                                  # 短信（需授权）
termux-tts-speak "hello"                              # 语音合成
termux-camera-photo out.jpg                           # 拍照（需授权）
```

---

## 9.2 ❌ 不能做的

| 限制 | 原因 | 绕过方式 |
|------|------|---------|
| 模拟点击其他 App | 需要 root 或 Shizuku | Shizuku |
| 读微信等 App 聊天记录 | 沙盒隔离 | 无 |
| 修改系统设置 | 无 root | 部分可用 ADB |
| 访问 `/data/data/` 其他应用目录 | SELinux（`untrusted_app_27` 域） | 无 |
| 让其他 App 开机自启 | 需系统权限 | 无 |
| 绑定 <1024 端口 | 非特权用户限制 | 用高端口 + 转发 |
| 装 Edge / Chrome | libc 架构不兼容 | 用 Firefox |

### 关于 `untrusted_app_27`

这是 Termux 的 SELinux 域：

```bash
$ id
uid=10246(<TERMUX_USER>) gid=10246(<TERMUX_USER>) ...
context=u:r:untrusted_app_27:s0:c246,c256,c512,c768
```

`untrusted_app_27` 表示这是一个**不受信任的应用进程**（Android 8.0+ 的策略版本）。这个域从一开始就被设计为低权限，很多操作会被 SELinux 直接拒绝：

```
avc: denied { ioctl } for path=/dev/pts/...
```

---

## 9.3 root 的取舍

| 维度 | 无 root（本方案） | 有 root |
|------|------------------|---------|
| **Termux 生命周期** | 靠音频焦点骗系统豁免 | 直接改系统策略 |
| **息屏保活** | 需持续播放静音（耗电） | 一条命令 |
| **自动化其他 App** | 不行（或用 Shizuku） | 完全可行 |
| **刷机风险** | 无 | 变砖、丢保修 |
| **系统更新** | 正常 OTA | 可能被阻断 |
| **银行 App** | 正常 | 部分会检测并拒绝运行 |

### 结论

对于「**跑脚本 + 图形桌面 + 跑 AI Agent**」这个目标，**无 root 完全够用**。

主要代价是：
1. 耗电增加（保活需要）
2. 不能控制其他 App

**除非有明确需求要操作微信这类 App，否则不建议 root。**

---

## 9.4 Shizuku：无 root 的权限增强

如果你想做「控制其他 App」这类事，但不想 root，考虑 Shizuku。

| 特性 | 说明 |
|------|------|
| 需要 root | ❌ 不需要 |
| 激活方式 | 用 ADB（USB 或无线调试）激活一次 |
| 持久性 | **重启后失效，需重新激活** |
| 能力 | 授予其他 App 调用系统级 API 的权限 |

### 典型用途

- Tasker / Automate 做无 root 自动化
- 冻结/卸载系统应用
- 模拟点击（部分工具通过 Shizuku 实现）
- 免 root 的权限管理

### 代价

每次手机重启后都要重新用 ADB 激活——这意味着需要一个能连 ADB 的环境（或者用 Android 11+ 的**无线调试**功能，可以在手机上自己激活）。

> Android 11+ 的无线调试让 Shizuku 激活不需要电脑——手机自身即可完成。

---

## 9.5 权限授予一览

本项目用到的所有权限操作：

```bash
# Doze 白名单（免息屏冻结）
adb shell dumpsys deviceidle whitelist +com.termux
adb shell dumpsys deviceidle whitelist +com.termux.api

# 后台运行
adb shell cmd appops set com.termux RUN_IN_BACKGROUND allow
adb shell cmd appops set com.termux RUN_ANY_IN_BACKGROUND allow
adb shell cmd appops set com.termux WAKE_LOCK allow

# Termux:API 媒体播放权限（保活需要）
adb shell pm grant com.termux.api android.permission.FOREGROUND_SERVICE
adb shell pm grant com.termux.api android.permission.WAKE_LOCK
adb shell pm grant com.termux.api android.permission.POST_NOTIFICATIONS
adb shell pm grant com.termux.api android.permission.READ_MEDIA_AUDIO
adb shell pm grant com.termux.api android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK
```

**注意**：`pm grant` 只能授予 `dangerous` 类权限。有些权限需要用户交互或在设置里手动开。

---

## 9.6 无法用 ADB 绕过的限制

即使有 ADB，也有做不到的：

| 限制 | 原因 |
|------|------|
| 给 Termux 注入命令 | Service 不导出（安全设计） |
| 读 Termux 沙盒内文件 | `run-as` 需要 debuggable 应用 |
| 长期持久化系统修改 | ADB shell 是临时会话 |
| 绕过 SELinux | 需要 root 或修改策略 |

---

## 下一步

→ [10-AI-Agent部署.md](10-AI-Agent部署.md)
