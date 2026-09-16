# 02 - SSH 连接

## 2.1 手机端：启动 SSH 服务

打开 Termux，依次执行：

```bash
# 1. 更新软件源（首次必须做）
pkg update && pkg upgrade -y

# 2. 装 SSH 服务端
pkg install openssh -y

# 3. 设置登录密码（输入时屏幕不显示字符，这是正常的）
passwd

# 4. 启动 SSH 服务
sshd

# 5. 查看用户名，记下来
whoami
```

> **注意端口是 8022**，不是标准的 22。Termux 故意避开 22 端口以免和系统冲突（非 root 应用无法绑定 <1024 的端口）。

---

## 2.2 电脑端：配置免密登录

### 生成密钥对

```bash
ssh-keygen -t ed25519 -N "" -C "fengair-to-termux" -f ~/.ssh/id_ed25519
```

- `-t ed25519`：现代算法，比 RSA 更短更安全
- `-N ""`：空密码，免交互（本地已登录的电脑上可以接受）
- `-C`：备注，方便识别这个密钥的用途

### 查看公钥

```bash
cat ~/.ssh/id_ed25519.pub
```

输出形如：
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...<YOUR_PUBLIC_KEY> fengair-to-termux
```

### 装到手机上

在手机 Termux 里执行：

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...<YOUR_PUBLIC_KEY> fengair-to-termux' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

> **权限很重要**：`~/.ssh` 必须 700，`authorized_keys` 必须 600。权限不对 sshd 会拒绝使用这个密钥（且不报错，只会在日志里体现）。

---

## 2.3 配置 SSH 别名

电脑上的 `~/.ssh/config`（Windows 路径 `C:\Users\<用户名>\.ssh\config`）：

```
Host nubia
    HostName nubia-m153
    User <TERMUX_USER>
    Port 8022
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

| 参数 | 作用 |
|------|------|
| `HostName nubia-m153` | 用 Tailscale 主机名（也可写 IP） |
| `User <TERMUX_USER>` | Termux 用户名，**必须改成你自己的** |
| `Port 8022` | Termux 的 SSH 端口 |
| `StrictHostKeyChecking accept-new` | 首次连接自动接受主机密钥，避免交互卡住 |
| `ServerAliveInterval 30` | 每 30 秒发心跳，防空闲断连 |
| `ServerAliveCountMax 3` | 心跳失败 3 次才判定断线 |

配好后：

```bash
ssh nubia
```

不用输密码直接进。

---

## 2.4 验证

```bash
ssh nubia 'echo OK; uname -a; whoami'
```

预期输出：
```
OK
Linux localhost 6.6.56-android15-... aarch64 Android
<TERMUX_USER>
```

---

## 2.5 常见问题

### Connection refused

**含义**：网络通，但 sshd 没在监听。

```bash
# 确认手机是否可达
ping <PHONE_IP>

# 确认端口
timeout 5 bash -c 'echo > /dev/tcp/<PHONE_IP>/8022' && echo 通 || echo 不通
```

ping 通但端口不通 → 手机在，但 Termux 里的 sshd 挂了。解法见 [06-ADB指南.md](06-ADB指南.md) 的救援流程。

### Connection timed out

**含义**：网络层就不通。

检查 Tailscale 状态、手机是否息屏休眠、手机是否在线。

### Permission denied (publickey)

```bash
# 在手机上检查权限
ls -la ~/.ssh/
# 应为 drwx------ .ssh 和 -rw------- authorized_keys
```

### 首次连接卡在 yes/no

`StrictHostKeyChecking accept-new` 没配上。临时解法：手动输 `yes`。

### 密钥对了还要输密码

sshd 没读到 `authorized_keys`。检查：
1. 公钥内容有没有换行断裂（必须**一行**）
2. 文件权限是否 600
3. 是否写到了正确的用户目录

---

## 下一步

→ [03-工具链与镜像源.md](03-工具链与镜像源.md)
