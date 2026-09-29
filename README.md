# arch-denial-setup

面向 **archinstall 最小化 Arch Linux** 的一键初始化脚本，装完即可进图形桌面。

## 一条命令搞定什么

| 模块 | 内容 |
|---|---|
| 仓库 | `archlinuxcn`（默认清华镜像）+ `archlinuxcn-keyring` → `paru`（CN 预编译，免构建） |
| 区域/字体 | `zh_CN.UTF-8` + `en_US.UTF-8` 兜底；全套 CJK 字体 + **Maple Mono NF 中文** |
| 驱动 | `nvidia-open-dkms` + `modeset=1 fbdev=1` + initramfs 早载（Wayland 硬前提） |
| 桌面 | **Denial**（Flutter Wayland 合成器，官方签名 pacman 仓库） |
| 输入法 | `fcitx5` 全家桶 + `GTK/QT/XMODIFIERS/SDL/GLFW` 环境变量 |
| 应用 | Kitty / Firefox(中文) / Nautilus / gnome-text-editor / eog / mpv |
| 迎宾 | `greetd` + `cosmic-greeter`（自动禁用冲突的 sddm/gdm） |
| polkit | `polkit` + `hyprpolkitagent`（Qt6 弹窗，随图形会话启动） |

## 用法

```bash
# 审查模式（普通用户即可，只打印不执行）
bash arch-denial-setup.sh --dry-run

# 实际执行
sudo bash arch-denial-setup.sh

# 老显卡（Maxwell 及更早）
NVIDIA_PKG=nvidia-dkms sudo bash arch-denial-setup.sh

# 换 archlinuxcn 镜像 / 跳过 Denial 仓库脚本
sudo bash arch-denial-setup.sh --cn-mirror https://mirrors.aliyun.com/archlinuxcn/\$arch
```

## 首次登录后

1. `reboot`（nvidia KMS 需重载）
2. cosmic-greeter 界面选 **Denial** 会话
3. `fcitx5-configtool` 添加拼音，`Ctrl+Space` 切换
4. Denial 黑屏 → 编辑 `/etc/denial/session.conf` 取消注释 `DENIAL_FLUTTER_RENDERER=skia`

## 说明

- **幂等可重跑**：仓库 stanza / locale / 环境变量 / mkinitcpio 模块都先检测再写。
- `paru` 装好后可直接 `paru -S <aur包>`。
- `denial` 是公开 Beta，接口/配置可能变；本脚本按当前 `v0.4.x` 行为编写。
