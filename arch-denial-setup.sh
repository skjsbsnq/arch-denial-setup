#!/usr/bin/env bash
#==============================================================================
# arch-denial-setup.sh
#
# archinstall 最小化 Arch Linux 一键初始化:
#   archlinuxcn + paru | zh_CN 区域/字体 | NVIDIA open-dkms + KMS
#   Denial (官方签名 pacman 仓库, Wayland 合成器) | fcitx5 中文输入法
#   Kitty / Firefox(中文) / Nautilus / gnome-text-editor / eog / mpv
#   greetd + cosmic-greeter 迎宾程序 | polkit + hyprpolkitagent
#
# 用法:
#   sudo bash arch-denial-setup.sh [--dry-run] [--skip-denial-repo]
#                                  [--cn-mirror <url>]
#
#   --dry-run           只打印将执行的命令 (普通用户也可运行, 便于先审查)
#   --skip-denial-repo  跳过 Denial 官方仓库安装脚本 (仓库已配置时)
#   --cn-mirror URL     archlinuxcn 镜像地址, 默认清华 TUNA
#
# 环境变量:
#   NVIDIA_PKG=nvidia-dkms   老卡 (Maxwell 及更早) 改用闭源分支
#   CN_MIRROR=<url>          同 --cn-mirror
#
# 幂等: 可重复执行; 已存在的配置会备份或跳过.
#==============================================================================
set -euo pipefail
IFS=$'\n\t'

#------------------------------ 配置 ------------------------------------------
NVIDIA_PKG="${NVIDIA_PKG:-nvidia-open-dkms}"   # Turing(16系/RTX20+) 适用 open
LOCALE="zh_CN.UTF-8"
FALLBACK_LOCALE="en_US.UTF-8"                  # 兜底 locale, 排错用
CN_MIRROR="${CN_MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch}"
DRY_RUN=0
SKIP_DENIAL_REPO=0

#------------------------------ 输出/执行工具 ---------------------------------
info(){ printf '\033[1;36m[*]\033[0m %s\n' "$*"; }
ok(){   printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
err(){  printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
die(){  err "$*"; exit 1; }
run(){  # 所有变更性命令都经 run, dry-run 下只打印
  if [ "$DRY_RUN" = 1 ]; then printf '\033[2mDRY>\033[0m %s\n' "$*"; else eval "$@"; fi
}
need(){ command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"; }
pac(){  run "pacman -S --needed --noconfirm $*"; }
wfile(){ # wfile <path>, 内容从 stdin 读; 自动建父目录
  local p="$1"
  if [ "$DRY_RUN" = 1 ]; then
    printf '\033[2mDRY>\033[0m write %s\n' "$p"; cat >/dev/null
  else
    mkdir -p "$(dirname "$p")"; cat > "$p"
  fi
}

#------------------------------ 参数解析 --------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)          DRY_RUN=1 ;;
    --skip-denial-repo) SKIP_DENIAL_REPO=1 ;;
    --cn-mirror)
      [ $# -ge 2 ] || die "--cn-mirror 需要参数"; CN_MIRROR="$2"; shift ;;
    -h|--help)          sed -n '1,30p' "$0"; exit 0 ;;
    *) warn "忽略未知参数: $1" ;;
  esac
  shift
done
# 镜像地址必须含 $arch 占位符, 缺则补
case "$CN_MIRROR" in *'$arch'*) ;; *) CN_MIRROR="${CN_MIRROR%/}/\$arch" ;; esac

#------------------------------ 前置检查 --------------------------------------
if [ "$DRY_RUN" != 1 ]; then
  [ "$(id -u)" -eq 0 ] || die "请以 root 运行: sudo bash $0"
fi
need pacman; need curl; need grep; need sed
ping -c1 -W3 archlinux.org >/dev/null 2>&1 || warn "网络检测未通过, 仍将继续"

info "内核: $(uname -r) | NVIDIA: $NVIDIA_PKG | archlinuxcn: $CN_MIRROR"
[ "$DRY_RUN" = 1 ] && warn "DRY-RUN: 以下命令不会真正执行"

#==============================================================================
# 1/8  archlinuxcn 仓库 + paru
#==============================================================================
info "==> [1/8] archlinuxcn 仓库 + paru"
if ! grep -q '^\[archlinuxcn\]' /etc/pacman.conf 2>/dev/null; then
  run "printf '\n[archlinuxcn]\nServer = %s\n' \"$CN_MIRROR\" >> /etc/pacman.conf"
fi
run "pacman -Sy --noconfirm"
pac "archlinuxcn-keyring"          # 导入 CN 仓库 GPG key
run "pacman -Sy --noconfirm"
pac "paru"                          # CN 仓库有编译好的 paru, 无需本地构建
ok "paru: $(pacman -Q paru 2>/dev/null || echo '待安装')"

#==============================================================================
# 2/8  基础组件 (Wayland 会话/音频/网络/seat/polkit agent)
#==============================================================================
info "==> [2/8] 基础组件 + polkit (hyprpolkitagent)"
pac "base-devel git curl wget sudo polkit hyprpolkitagent \
     networkmanager seatd \
     pipewire pipewire-pulse pipewire-alsa wireplumber \
     xdg-user-dirs xdg-desktop-portal dbus mesa libinput libxkbcommon"
run "systemctl enable --now NetworkManager.service"
run "systemctl enable --now seatd.service || true"   # Denial 依赖 seatd

# polkit 密码弹窗: hyprpolkitagent 是 systemd --user 服务,
# 挂到 graphical-session.target.wants, 随 Denial 会话自动拉起
run "mkdir -p /etc/systemd/user/graphical-session.target.wants"
run "ln -sf /usr/lib/systemd/user/hyprpolkitagent.service \
     /etc/systemd/user/graphical-session.target.wants/hyprpolkitagent.service"

#==============================================================================
# 3/8  中文语言/区域 + 字体
#==============================================================================
info "==> [3/8] $LOCALE 区域 + 中文字体"
for L in "$LOCALE" "$FALLBACK_LOCALE"; do
  if ! grep -q "^$L" /etc/locale.gen 2>/dev/null; then
    run "sed -i 's/^#[[:space:]]*$L/$L/' /etc/locale.gen"
    grep -q "^$L" /etc/locale.gen 2>/dev/null || run "echo '$L UTF-8' >> /etc/locale.gen"
  fi
done
run "locale-gen"
wfile /etc/locale.conf <<EOF
LANG=$LOCALE
EOF
pac "noto-fonts noto-fonts-cjk noto-fonts-emoji wqy-microhei \
     adobe-source-han-sans-cn-fonts ttf-dejavu \
     ttf-maplemono-nf-cn-unhinted"   # Maple Mono NF 中文 (archlinuxcn)
run "fc-cache -f >/dev/null 2>&1 || true"
ok "LANG=$LOCALE (其余 LC_* 默认, 终端/日志保持英文便于排错)"

#==============================================================================
# 4/8  NVIDIA 驱动 + KMS/modeset (Wayland 合成器的硬前提)
#==============================================================================
info "==> [4/8] $NVIDIA_PKG + KMS"
# 按已安装内核包自动选 headers (linux / linux-lts / linux-zen ...)
HEADERS=linux-headers
for k in linux linux-lts linux-zen linux-hardened; do
  if pacman -Q "$k" >/dev/null 2>&1; then HEADERS="$k-headers"; break; fi
done
info "内核头文件包: $HEADERS"
pac "$HEADERS $NVIDIA_PKG nvidia-utils nvidia-settings"

wfile /etc/modprobe.d/nvidia.conf <<'EOF'
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

# nvidia 模块放进 initramfs MODULES (早载 KMS); 幂等
if grep -q 'nvidia_drm' /etc/mkinitcpio.conf 2>/dev/null; then
  info "mkinitcpio MODULES 已包含 nvidia 模块, 跳过"
else
  run "sed -i -E 's/^MODULES=\\(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /etc/mkinitcpio.conf"
  if [ "$DRY_RUN" != 1 ] && ! grep -q 'nvidia_drm' /etc/mkinitcpio.conf; then
    warn "未能写入 mkinitcpio MODULES, 请手动检查 /etc/mkinitcpio.conf"
  fi
fi
run "mkinitcpio -P"
run "systemctl enable nvidia-suspend nvidia-resume nvidia-hibernate 2>/dev/null || true"
ok "NVIDIA 驱动就绪 (重启后生效)"

#==============================================================================
# 5/8  Denial Wayland 合成器 (官方签名仓库)
#==============================================================================
info "==> [5/8] Denial"
if [ "$SKIP_DENIAL_REPO" = 1 ]; then
  info "--skip-denial-repo: 跳过仓库安装脚本"
elif grep -qiE '^\[(denial|denialwm)\]' /etc/pacman.conf 2>/dev/null; then
  info "Denial 仓库已在 pacman.conf 中, 跳过安装脚本"
else
  info "运行 Denial 官方仓库安装脚本 (添加签名 pacman 仓库)"
  run "sh -c 'curl -fsSL https://install.denialwm.org | sh'"
fi
run "pacman -Syu --noconfirm"
pac "denial"

wfile /etc/denial/session.conf <<'EOF'
# Denial 会话覆盖配置 (key=value, 重启会话生效)
# 黑屏/渲染异常时取消下一行注释, 退回 Skia 兼容渲染:
# DENIAL_FLUTTER_RENDERER=skia
#
# 显示控制器与 GPU 是不同 DRM 节点时手动指定:
# DENIAL_DRM_DEVICE=/dev/dri/card0
# DENIAL_RENDER_DEVICE=/dev/dri/renderD128
EOF
ok "Denial 就绪, 会话入口 /usr/bin/denial-session"

#==============================================================================
# 6/8  fcitx5 中文输入法 + 环境变量
#==============================================================================
info "==> [6/8] fcitx5"
pac "fcitx5 fcitx5-configtool fcitx5-qt fcitx5-gtk \
     fcitx5-chinese-addons fcitx5-material-color"

ENV=/etc/environment
run "touch $ENV"
setenv(){ # setenv KEY VALUE, 幂等更新 /etc/environment
  if grep -q "^$1=" "$ENV" 2>/dev/null; then
    run "sed -i 's|^$1=.*|$1=$2|' $ENV"
  else
    run "echo '$1=$2' >> $ENV"
  fi
}
setenv GTK_IM_MODULE   fcitx        # GTK 应用
setenv QT_IM_MODULE    fcitx        # Qt 应用 (含 hyprpolkitagent Qt6)
setenv XMODIFIERS      '@im=fcitx'  # XWayland/老应用 (Firefox X11 模式等)
setenv SDL_IM_MODULE   fcitx        # SDL 游戏
setenv GLFW_IM_MODULE  ibus         # GLFW 仅有 ibus 前端, fcitx5 兼容之
setenv INPUT_METHOD    fcitx
setenv MOZ_ENABLE_WAYLAND 1         # Firefox 原生 Wayland

# 会话自启 (XDG autostart; Arch 包一般自带, 此处兜底)
if [ -f /usr/share/applications/org.fcitx.Fcitx5.desktop ] || [ "$DRY_RUN" = 1 ]; then
  run "install -Dm644 /usr/share/applications/org.fcitx.Fcitx5.desktop \
       /etc/xdg/autostart/org.fcitx.Fcitx5.desktop"
fi
ok "fcitx5 就绪; 登录后用 fcitx5-configtool 添加拼音"

#==============================================================================
# 7/8  应用软件
#==============================================================================
info "==> [7/8] Kitty / Firefox / Nautilus / 编辑器 / eog / mpv"
pac "kitty firefox firefox-i18n-zh-cn \
     nautilus gvfs gnome-text-editor eog mpv"

#==============================================================================
# 8/8  迎宾: greetd + cosmic-greeter (不装 sddm, 避免 DM 冲突)
#==============================================================================
info "==> [8/8] greetd + cosmic-greeter"
pac "greetd cosmic-greeter"   # 依赖自动带入 cosmic-comp / greetd / icon-theme

# cosmic-greeter 包自带 /etc/greetd/cosmic-greeter.toml 会话定义, 直接采用
if [ -f /etc/greetd/cosmic-greeter.toml ] || [ "$DRY_RUN" = 1 ]; then
  if [ -f /etc/greetd/config.toml ]; then
    run "cp /etc/greetd/config.toml /etc/greetd/config.toml.bak"
  fi
  run "cp /etc/greetd/cosmic-greeter.toml /etc/greetd/config.toml"
else
  wfile /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "cosmic-comp /usr/bin/cosmic-greeter-start"
user = "cosmic-greeter"
EOF
fi

# 已存在的其它 DM 会与 greetd 抢 VT, 统一禁用
for dm in sddm gdm lightdm ly lxdm; do
  if systemctl is-enabled "$dm" >/dev/null 2>&1; then
    warn "禁用显示管理器 $dm (与 greetd 冲突)"
    run "systemctl disable $dm.service"
  fi
done
run "systemctl enable cosmic-greeter-daemon.service 2>/dev/null || true"
run "systemctl enable greetd.service"

# 普通用户加入 seat/input/video/render 组 (seatd/greetd 路径需要)
TGT="${SUDO_USER:-$(getent passwd | awk -F: '$3>=1000 && $3<60000 {print $1; exit}')}"
if [ -n "$TGT" ]; then
  run "usermod -aG seat,input,video,render $TGT"
  ok "用户 $TGT 已加入 seat/input/video/render 组"
else
  warn "未检测到普通用户, 请手动: usermod -aG seat,input,video,render <user>"
fi

#==============================================================================
echo
ok "================ 全部完成 ================"
cat <<'EOF'
后续步骤:
  1) reboot                        # nvidia KMS 模块需重启加载
  2) cosmic-greeter 登录界面中选择 Denial 会话
  3) Denial 黑屏 -> 编辑 /etc/denial/session.conf
     取消注释 DENIAL_FLUTTER_RENDERER=skia
  4) fcitx5-configtool 添加 Pinyin; Ctrl+Space 切换输入法
  5) 旧卡 (Maxwell 及更早): NVIDIA_PKG=nvidia-dkms 重跑第 4 步
  6) paru 已可用: paru -S <aur包>
  7) polkit 密码弹窗由 hyprpolkitagent 提供, 已随图形会话启用
EOF
