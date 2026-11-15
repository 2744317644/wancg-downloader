# iPhone 真机控制与调试使用说明

本文记录当前 Windows 机器上用来**查看 iPhone 屏幕、点击/滑动/输入、截图**的工具链。
它不是自研 App，而是基于 `pymobiledevice3` 的 CoreDevice 服务封装；Windows 上不需要 Xcode。

> 适用设备：`封智予的iPhone`（UDID `00008150-000515191A28C01C`，iOS 27.3）
> 适用电脑：当前 Windows 11 + iTunes/Apple Mobile Device Service 已安装
> 本机 Python：`C:\Users\柠墨白\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe`

---

## 1. 先设置快捷变量

在 PowerShell 里执行一次，后面命令都可以直接复制：

```powershell
$py = "$env:USERPROFILE\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe"
function pd3 { & $py -m pymobiledevice3 @args }
```

确认工具可用：

```powershell
pd3 --help
pd3 usbmux list
```

如果 `usbmux list` 是空数组，但手机确实连着，先看文末「常见问题」。

> 如果提示 `pymobiledevice3` 不存在，执行：
> `& $py -m pip install -U pymobiledevice3`

---

## 2. 挂载 Developer Disk Image（每次重启/重插后做一次）

多数 `developer core-device ...` 命令都依赖 DDI：

```powershell
pd3 mounter auto-mount
pd3 mounter list
```

看到 personalized DDI 已挂载即可。手机需要：

- 已用数据线连接电脑；
- 已解锁并信任这台电脑；
- 设置 → 隐私与安全性 → 开发者模式 已打开。

---

## 3. 实时看屏幕 + 直接在浏览器操作

这是最接近「远程控制 iPhone」的方式：

```powershell
pd3 developer core-device display serve-web --http-port 8080
```

然后浏览器打开：

```text
http://127.0.0.1:8080/
```

网页里的操作方式：

- **单击画面** = 点击 iPhone；
- **按住拖动** = 滑动/拖拽；
- **键盘输入** = 在 canvas 获得焦点时发送到 iPhone；
- 页面上的按钮 = Home、锁屏、音量、旋转等；
- `Ctrl+H` = Home，`Ctrl+L` = 锁屏；更多快捷键在页面帮助里。

停止：在 PowerShell 按 `Ctrl+C`。

### 关于旋转

实测 `serve-web` 有时会把竖屏画面画进横向画布，看起来像横过来了。
先点网页里的 **View → Rotate ↺ / Rotate ↻** 旋正即可；命令行截图不受这个 bug 影响。

### 安全提醒

默认只绑定 `127.0.0.1`，所以只有本机能访问，这是推荐用法。

不要把端口直接暴露到局域网。确实需要手机/另一台电脑访问时，至少加：

```powershell
pd3 developer core-device display serve-web `
  --bind 0.0.0.0 --http-port 8080 --password "换一个强密码" --https
```

---

## 4. 命令行截图

```powershell
pd3 developer core-device screen-capture screenshot .\phone.png
```

文件会保存在当前 PowerShell 目录。
截图是 iPhone 的真实分辨率，例如当前设备是 `1206 × 2622`。

截图前先确认：

```powershell
pd3 developer core-device get-display-info
```

输出里可以看到当前 display 的像素尺寸和方向。

---

## 5. 点击、滑动、输入

### 5.1 坐标规则

HID 命令使用 **0..65535 的归一化坐标**：

- `0,0` = 屏幕左上角
- `65535,65535` = 屏幕右下角

换算公式：

```text
x_hid = round(x_pixel / screen_width  * 65535)
y_hid = round(y_pixel / screen_height * 65535)
```

以 `1206 × 2622` 为例：

| 屏幕位置 | 像素坐标 | HID 坐标 |
|---|---:|---:|
| 屏幕正中心 | 603, 1311 | `32768 32768` |
| 左上角返回按钮 | 80, 140 | `4347 3499` |
| 靠下 3/4 处 | 603, 1967 | `32768 49166` |

### 5.2 点击

```powershell
# 点击屏幕正中心
pd3 developer core-device universal-hid-service tap 32768 32768
```

### 5.3 拖动 / 滑动

```powershell
# 手指从屏幕下方滑到上方：内容向上滚（看下面的内容）
pd3 developer core-device universal-hid-service drag 32768 50000 32768 22000 --duration 0.25 --steps 20

# 横向滑动：从右向左
pd3 developer core-device universal-hid-service drag 60000 32768 6000 32768 --duration 0.25 --steps 20
```

参数说明：

- 第 1、2 个参数 = 起点；
- 第 3、4 个参数 = 终点；
- `--duration` 默认 0.6 秒，太快会被 iOS 识别成 flick；
- `--steps` 默认 30，滑动距离长时可以适当增加。

> 方向和「内容滚动」相反：手指向上滑 = 内容向下翻。

### 5.4 输入文字

```powershell
pd3 developer core-device universal-hid-service type "hello world"
```

只支持可打印 ASCII。中文/emoji 建议用 `serve-web` 的剪贴板面板，或者先写入设备剪贴板：

```powershell
pd3 developer core-device copy "要粘贴的中文"
```

然后手动长按输入框选择粘贴。

### 5.5 硬件按键

```powershell
pd3 developer core-device hid button home
pd3 developer core-device hid button lock
pd3 developer core-device hid button volume-up
pd3 developer core-device hid button volume-down
pd3 developer core-device hid button siri
```

### 5.6 旋转屏幕

```powershell
pd3 developer core-device rotate left
```

连续四次转一圈。

---

## 6. 常用排查 / 辅助命令

```powershell
# 设备信息
pd3 developer core-device get-device-info

# 屏幕尺寸、方向
pd3 developer core-device get-display-info

# 已安装 App 列表
pd3 developer core-device list-apps

# 启动 App（例如 wnacg）
pd3 developer core-device launch-application com.wancg.downloader

# 查看当前界面深色/浅色模式
pd3 developer core-device user-interface-style

# 切换深色模式
pd3 developer core-device user-interface-style dark

# 读取设备剪贴板文本
pd3 developer core-device paste

# 写入设备剪贴板
pd3 developer core-device copy "hello"
```

`pymobiledevice3` 还提供：

```powershell
pd3 usbmux list
pd3 usbmux forward 8100 8100
pd3 syslog live
pd3 processes list
```

需要哪一项时可以先 `pd3 <命令> --help`。

---

## 7. 常用流程

### 查看 App 当前界面并点按钮

```powershell
pd3 mounter auto-mount
pd3 developer core-device screen-capture screenshot .\before.png
pd3 developer core-device universal-hid-service tap 32768 32768
Start-Sleep -Seconds 1
pd3 developer core-device screen-capture screenshot .\after.png
```

对比两张截图，确认点击是否生效。
真实设备上的点击有真实后果，**不要对不认识的可疑控件试坐标**。

### 在阅读器里翻页

```powershell
# 向上滑：看下一屏
pd3 developer core-device universal-hid-service drag 32768 52000 32768 18000 --duration 0.22 --steps 18
```

### 用实时窗口手动操作

```powershell
pd3 mounter auto-mount
pd3 developer core-device display serve-web --http-port 8080
```

浏览器打开 `http://127.0.0.1:8080/`，接下来直接用鼠标和键盘。

---

## 8. 常见问题

### `usbmux list` 返回 `[]`

按顺序检查：

1. iPhone 是否解锁、是否点了「信任此电脑」；
2. 换一根支持数据的线，不要用纯充电线；
3. Windows 服务是否运行：
   ```powershell
   Get-Service "Apple Mobile Device Service"
   ```
   状态应为 `Running`；没运行则：
   ```powershell
   Start-Service "Apple Mobile Device Service"
   ```
4. 重新插拔手机后再执行 `pd3 usbmux list`。

当前机器上该服务默认监听 `127.0.0.1:27015`，这是 iTunes/Apple 服务的 usbmuxd 端口，不需要手动改。

### `Could not start screenshotr service` / `Developer Disk Image not mounted`

```powershell
pd3 mounter auto-mount
```

还不行就确认「开发者模式」已开启，然后重新插拔、重启手机。

### `tap` 执行了但屏幕没反应

- 手机是否锁屏？先 `pd3 developer core-device hid button home` 唤醒并解锁；
- DDI 是否挂载？
- App 是否在前台？
- 点击坐标是否落在控件上？先用截图 + `get-display-info` 再换算。

### `serve-web` 打不开或黑屏

- 端口被占用：换一个端口，例如 `--http-port 8081`；
- 浏览器用最新版 Chrome/Edge；
- 确认是 iOS 27+（本机是 iOS 27.3，支持）；
- 网络/代理软件可能拦截 localhost，临时关闭代理再试；
- 页面里点 **Force Restart** 或重新执行命令。

### 画面横过来了

点网页的 **View → Rotate ↺ / Rotate ↻**。
这是 `serve-web` 的已知显示问题，命令行截图始终是正确的竖屏。

### 中文输入

`universal-hid-service type` 只支持 ASCII。
中文用浏览器实时窗口的剪贴板同步，或：

```powershell
pd3 developer core-device copy "中文内容"
```

然后在手机上手动粘贴。

---

## 9. 与 DSH 自带 iOS 工具的区别

DSH 的 `ios_sim_*` / `ios_real_start_wda` 工具需要 macOS + Xcode 构建 WebDriverAgent；
当前是 Windows 环境，所以实际使用的是本指南的 `pymobiledevice3` 方案。

如果以后换到 Mac，可以优先用 DSH 原生工具做无障碍树/元素定位；
在 Windows 上，用本指南的截图 + 归一化坐标最直接。

---

## 10. 隐私与安全

- 不要把 App/网站截图上传到公开仓库或 Release；
- 批量操作前先确认当前前台 App 和页面；
- 真实设备上的删除、发布、购买、发消息等点击不可撤销；
- 实时窗口默认只监听 `127.0.0.1`，不要无密码暴露到公网；
- 本机截图默认放在本地目录（如 `.gh-artifacts/`），不要提交进 Git。
