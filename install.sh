#!/data/data/com.termux/files/usr/bin/bash
# install.sh – Termux → Debian XFCE qua Termux X11 (không VNC)
# Hỏi tên user & password khi setup, tạo user thường + sudo NOPASSWD
set -euo pipefail

say()  { printf "\033[1;32m[*]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }
trap 'err "Script lỗi ở dòng $LINENO"; exit 1' ERR

# 0) Bắt buộc chạy trong Termux
[ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ] || { err "Không phải môi trường Termux."; exit 1; }

# 1) Hỏi tên user & mật khẩu
DEFAULT_USER="droid"
read -rp "Nhập tên user Debian [${DEFAULT_USER}]: " USER_NAME
USER_NAME="${USER_NAME:-$DEFAULT_USER}"

# Kiểm tra đơn giản: chữ, số, gạch dưới, dài 1-32
if ! [[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  err "Tên user không hợp lệ. Chỉ dùng chữ thường, số, gạch dưới/gạch nối (bắt đầu bằng chữ hoặc _)."
  exit 1
fi

# Hỏi password 2 lần (ẩn)
while true; do
  read -srp "Đặt mật khẩu cho ${USER_NAME}: " USER_PASS_1; echo
  read -srp "Nhập lại mật khẩu: " USER_PASS_2; echo
  if [ -z "$USER_PASS_1" ]; then
    warn "Mật khẩu trống, vui lòng nhập lại."
    continue
  fi
  if [ "$USER_PASS_1" != "$USER_PASS_2" ]; then
    warn "Mật khẩu không khớp, thử lại."
  else
    break
  fi
done
USER_PASS="$USER_PASS_1"
unset USER_PASS_1 USER_PASS_2

# 2) Cập nhật & cài gói Termux
say "Cập nhật Termux & cài gói cần thiết…"
pkg update -y && pkg upgrade -y
pkg install -y x11-repo proot-distro pulseaudio
pkg install -y virglrenderer-android >/dev/null 2>&1 || true   # tùy chọn

# 3) Cài Debian nếu CHƯA có (thử login thay vì grep)
if proot-distro login debian -- true >/dev/null 2>&1; then
  say "Debian đã tồn tại, bỏ qua bước cài."
else
  say "Cài Debian…"
  proot-distro install debian
fi

# 4) Bootstrap bên trong Debian (GUI, sudo, user, shm, locale)
say "Cấu hình Debian (XFCE, dbus-x11, firefox-esr, fonts, sudo, user)…"
# Truyền biến qua env cho an toàn khi có ký tự đặc biệt
proot-distro login debian -- env USER_NAME="$USER_NAME" USER_PASS="$USER_PASS" bash -lc '
  set -e
  export DEBIAN_FRONTEND=noninteractive

  apt update
  apt install -y xfce4 xfce4-goodies dbus-x11 x11-apps \
                 firefox-esr thunar thunar-archive-plugin p7zip-full \
                 pulseaudio-utils fonts-dejavu fonts-noto fonts-noto-cjk \
                 mousepad vlc sudo

  # shared memory cho app X11
  mkdir -p /dev/shm && chmod 1777 /dev/shm

  # tạo user nếu chưa có
  if ! id -u "$USER_NAME" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$USER_NAME"
  fi

  # đặt mật khẩu
  echo "$USER_NAME:$USER_PASS" | chpasswd

  # thêm sudo + NOPASSWD
  usermod -aG sudo "$USER_NAME"
  echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/99-$USER_NAME"
  chmod 0440 "/etc/sudoers.d/99-$USER_NAME"

  # locale cơ bản
  if ! locale -a | grep -qi "en_US.utf8"; then
    apt install -y locales
    sed -i "s/^# *en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen || true
    locale-gen en_US.UTF-8 || true
    update-locale LANG=en_US.UTF-8 || true
  fi
'

# 5) Tạo launcher ~/start-debian-x11 (đăng nhập bằng user vừa tạo)
say "Tạo launcher ~/start-debian-x11…"
cat > "$HOME/start-debian-x11" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Launcher chạy Debian XFCE qua Termux X11 (không VNC)
set -euo pipefail

say()  { printf "\033[1;32m[*]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }

# Đọc USER_NAME đã lưu khi cài
CFG="$HOME/.debian-x11.conf"
if [ -f "$CFG" ]; then . "$CFG"; fi
: "${USER_NAME:=droid}"

# 1) Khởi động PulseAudio nếu chưa chạy
if ! pgrep -x pulseaudio >/dev/null 2>&1; then
  say "Khởi động PulseAudio…"
  pulseaudio --start \
    --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 listen=127.0.0.1" \
    --exit-idle-time=-1
fi

# 2) (Tuỳ chọn) Tăng tốc 3D với virgl
if command -v virgl_test_server_android >/dev/null 2>&1; then
  if ! pgrep -f virgl_test_server_android >/dev/null 2>&1; then
    say "Bật virgl (tăng tốc 3D)…"
    nohup virgl_test_server_android >/dev/null 2>&1 &
    sleep 0.2
  fi
fi

# 3) Biến môi trường cho X11 & âm thanh
export DISPLAY=:0
export PULSE_SERVER=127.0.0.1
# Nếu app 3D lỗi, comment 2 dòng dưới:
export MESA_GL_VERSION_OVERRIDE=4.5
export GALLIUM_DRIVER=virpipe

# 4) Đảm bảo startxfce4 có trong Debian
if ! proot-distro login debian -- bash -lc "command -v startxfce4 >/dev/null 2>&1"; then
  err "Thiếu startxfce4. Hãy chạy lại: install.sh"
  exit 1
fi

# 5) Nhắc mở Termux X11
warn "Hãy mở ứng dụng Termux X11 (màn hình đen) trước khi tiếp tục."
sleep 1

# 6) Vào Debian dưới user thường & khởi động XFCE
#    - Bind $PREFIX/tmp → /tmp và /dev/shm
#    - Bind trực tiếp socket X11: $PREFIX/tmp/.X11-unix → /tmp/.X11-unix
#    - XAUTHORITY rỗng để tránh trỏ sai file
proot-distro login debian \
  --user "$USER_NAME" \
  --bind "$PREFIX/tmp:/tmp" \
  --bind "$PREFIX/tmp/.X11-unix:/tmp/.X11-unix" \
  --bind "$PREFIX/tmp:/dev/shm" \
  -- env -u WAYLAND_DISPLAY \
     DISPLAY=":0" PULSE_SERVER="$PULSE_SERVER" XAUTHORITY= \
     dbus-launch startxfce4
EOF
chmod +x "$HOME/start-debian-x11"

# 6) Lưu cấu hình user cho launcher (không lưu mật khẩu)
printf 'USER_NAME=%s\n' "$USER_NAME" > "$HOME/.debian-x11.conf"

# 7) Alias tiện
grep -q 'start-debian-x11' "$HOME/.bashrc" 2>/dev/null || \
  echo 'alias debian-x11="~/start-debian-x11"' >> "$HOME/.bashrc"

say "Hoàn tất!"
printf "\n👉 Bước tiếp theo:\n"
printf "  1) Cài & mở ứng dụng Termux X11 (APK).\n"
printf "  2) Quay lại Termux và chạy: \033[1m~/start-debian-x11\033[0m\n"
printf "     (hoặc: \033[1mdebian-x11\033[0m nếu đã mở session mới)\n"
