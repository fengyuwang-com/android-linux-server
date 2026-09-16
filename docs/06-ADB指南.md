# 06 - ADB 指南

ADB（Android Debug Bridge）是"终极后门"，**权限比 SSH 高得多**，能干 SSH 干不了的事。

## 6.1 首次配置

### 手机端

1. 设置 → 关于手机 → 版本号，**连点 7 次** → 开启开发者选项
2. 设置 → 系统 → 开发者选项 → 打开 **USB 调试**
3. 用数据线连电脑
4. 下拉通知栏，把 USB 模式改成 **传输文件 (MTP)**
5. 手机弹出"允许 USB 调试吗？" → 勾选**始终允许** → 确定

### 电脑端验证

```bash
adb devices
```

预期输出：

```
List of devices attached
<ADB_SERIAL>      device product:pacific model:P0110 device:pacific transport_id:2
```

| 状态 | 含义 |
|------|------|
| `device` | ✅ 正常，可以操作 |
| `unauthorized` | 手机上没确认授权 |
| `offline` | 连接不稳定，试 `adb reconnect` |
| 空列表 | 没识别到，检查 USB 模式和线材 |

### ⚠️ 坑：Windows 报"未知 USB 设备(设备描述符请求失败)"

**不是驱动问题**，是手机的 USB 模式不对。

**解法**：拔掉数据线，重新插，然后在手机下拉通知栏里选 **传输文件 (MTP)**（不是"仅充电"）。

正确的 USB 模式才让手机作为设备正常枚举。设置好一次后通常会记住。

---

## 6.2 ADB 路径

winget 装的 ADB 在这个位置：

```
C:\Users\<用户名>\AppData\Local\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe
```

**在 Git Bash 里使用**：

```bash
export ADB="/c/Users/<YourName>/AppData/Local/Microsoft/WinGet/Packages/Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe/platform-tools/adb.exe"
"$ADB" devices
```

定位方法：
```bash
where.exe adb
find /c/Users/<用户名> -maxdepth 6 -iname "adb.exe" 2>/dev/null
```

---

## 6.3 常用命令

### 基础

```bash
# 设备列表
adb devices -l

# 进入 shell
adb shell

# 重启 ADB 服务（连接异常时）
adb kill-server && adb start-server

# 重连
adb reconnect
```

### 屏幕控制

```bash
# 唤醒屏幕
adb shell input keyevent KEYCODE_WAKEUP

# 息屏
adb shell input keyevent KEYCODE_SLEEP

# 解锁（上滑）
adb shell input swipe 540 1800 540 600 200

# 查看屏幕亮灭状态
adb shell dumpsys power | grep "mWakefulness="
# mWakefulness=Awake   ← 亮
# mWakefulness=Asleep  ← 灭

# 查看当前前台窗口
adb shell dumpsys window | grep "mCurrentFocus"
```

### 应用控制

```bash
# 启动 App
adb shell am start -n com.termux/.app.TermuxActivity

# 强制杀掉 App
adb shell am force-stop com.termux

# 查看运行中的进程
adb shell ps -A | grep termux

# 已安装包列表
adb shell pm list packages | grep termux
```

### 安装 / 权限

```bash
# 安装 APK（-r 覆盖安装）
adb install -r xxx.apk

# 授予权限
adb shell pm grant <包名> <权限名>

# 撤销权限
adb shell pm revoke <包名> <权限名>

# 给 App 加 Doze 白名单
adb shell dumpsys deviceidle whitelist +com.termux

# 允许后台运行
adb shell cmd appops set com.termux RUN_IN_BACKGROUND allow
```

### 电量 / 温度

```bash
adb shell dumpsys battery | grep -E "level|temperature"
# temperature 单位是 0.1°C，如 320 = 32.0°C
```

---

## 6.4 ⭐ 救援流程：SSH 断了怎么办

这是 ADB 最有价值的用途。

### 判断问题在哪

```bash
# 1. 手机网络通不通
ping <PHONE_IP>

# 2. SSH 端口通不通
timeout 5 bash -c 'echo > /dev/tcp/<PHONE_IP>/8022' && echo "端口通" || echo "端口不通"
```

| ping | 端口 | 结论 |
|------|------|------|
| ✅ | ✅ | SSH 正常，问题在别处 |
| ✅ | ❌ | **手机在，sshd 挂了** → 用下面的流程 |
| ❌ | ❌ | 手机不在线（息屏休眠 / 没网 / Tailscale 掉线） |

### 救援步骤

```bash
export ADB="/c/Users/.../platform-tools/adb.exe"

# 1. 确认设备和 Termux 进程
"$ADB" devices
"$ADB" shell ps -A | grep termux

# 2. 唤醒屏幕（如果需要）
"$ADB" shell input keyevent KEYCODE_WAKEUP

# 3. 重启 Termux —— 这一步触发 .bashrc 自启 sshd
"$ADB" shell am force-stop com.termux
sleep 3
"$ADB" shell am start -n com.termux/.app.TermuxActivity

# 4. 等 12-15 秒，验证
sleep 15
timeout 8 bash -c 'echo > /dev/tcp/<PHONE_IP>/8022' && echo "✅ SSH 恢复" || echo "❌ 还不行"
```

### 为什么这招有效

`am force-stop` + 重新启动 Termux 会创建一个**全新的登录会话**，触发 `.bashrc` 执行，而 `.bashrc` 里有拉起 sshd 的逻辑。

这是 ADB 唯一可靠的救援手段。

### ⚠️ 不能做什么：ADB 无法直接给 Termux 发命令

试过但**不可行**的路径：

```bash
# ❌ 报错：Requires permission not exported from uid 10246
adb shell am startservice -n com.termux/com.termux.app.TermuxService \
  -a com.termux.service_execute -d /path/to/script.sh

# ❌ 返回 result=0 但无实际效果
adb shell am broadcast -a com.termux.api.RUN_COMMAND \
  --es com.termux.api.extra.COMMAND "sshd" \
  com.termux.api/.RunCommandService

# ❌ run-as 不可用（正式版 Termux 不是 debuggable）
adb shell run-as com.termux cat /data/data/com.termux/files/home/.bashrc
# run-as: package not debuggable: com.termux
```

**原因**：Termux 的 Service 明确声明**不导出**（防止其他 App 注入命令），ADB 的 shell uid（2000）也进不去。

**结论**：不要指望 ADB 给 Termux 发命令，只能靠 force-stop + 重启这条路径。

---

## 6.5 ADB 与 SSH 的分工

| 场景 | 用哪个 | 原因 |
|------|--------|------|
| 日常跑命令 | SSH | 方便，不用插线 |
| 息屏后失联 | **ADB** | 能唤醒屏幕 |
| sshd 挂了 | **ADB** | 能重启 Termux 触发自愈 |
| 改系统设置 | **ADB** | 权限更高 |
| 装 APK | **ADB** | `adb install` |
| 授予权限 | **ADB** | SSH 做不到 |
| 传文件 | 都行 | `scp` 或 `adb push` |

---

## 6.6 Shizuku：ADB 权限的"持久化"

**问题**：ADB 需要插 USB 线，不能远程用。

**Shizuku** 解决了这个：它用 ADB 激活一次，然后把部分系统级 API 权限**持久授权**给其他 App，之后不需要线。

| 特性 | 说明 |
|------|------|
| 需要 root | ❌ 不需要 |
| 激活方式 | 每次重启后需重新用 ADB（或无线调试）激活 |
| 能力 | 授予 App 调用系统 API 的权限（如控制其他 App、免 root 自动化） |
| 生效范围 | 重启后失效，需重新激活 |

适合场景：需要用 Tasker / Automate 之类工具做自动化，但不想 root。

---

## 下一步

→ [07-自愈机制.md](07-自愈机制.md)
