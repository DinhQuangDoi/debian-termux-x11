#!/data/data/com.termux/files/usr/bin/bash
# install.sh – Termux → Debian XFCE qua Termux X11 (không VNC)
# - Hỏi user/pass
# - Cấu hình Debian (XFCE, âm thanh, fonts, sudo)
# - Tạo launcher ngắn: dx

set -euo pipefail

# ==== TÙY CHỌN ====
LAUNCHER_NAME="${LAUNCHER_NAME:-dx}"   # tên lệnh khởi động ngắn
DEFAULT_USER="droid"
# ===================

say()  { printf "\033[1;32m[*]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }
trap 'err "Script lỗi ở dòng $LINENO"; exit 1' ERR

# 0) Bắt buộc Termux
[ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ] || { err "Không phải môi trường Termux."; exit 1; }

# 1) Hỏi user/pass
read -rp "Nhập tên user Debian [${DEFAULT_USER}]: " USER_NAME
USER_NAME="${USER_NAME:-$DEFAULT_USER}"
[[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { err "Tên user không hợp lệ."; }

while true; do
  read -srp "Đặt mật khẩu cho ${USER_NAME}: " USER_PASS_1; echo
  read -srp "Nhập lại mật khẩu: " USER_PASS_2; echo
  [ -n "$USER_PASS_1" ] || { warn "Mật khẩu trống, nhập lại."; continue; }
  [ "$USER_PASS_1" = "$USER_PASS_2" ] && break || warn "Không khớp, thử lại."
done
USER_PASS="$USER_PASS_1"; unset USER_PASS_1 USER_PASS_2

# 2) Gói Termux
say "Cập nhật & cài gói Termux…"
pkg update -y && pkg upgrade -y
pkg install -y x11-repo proot-distro pulseaudio termux-x11
pkg install -y virglrenderer-android >/dev/null 2>&1 || true  # tùy chọn

# 3) Cài Debian nếu chưa có
if proot-distro login debian -- true >/dev/null 2>&1; then
  say "Debian đã tồn tại."
else
  say "Cài Debian…"
  proot-distro install debian
fi

# 4) Bootstrap Debian
say "Cấu hình Debian (XFCE, dbus-x11, firefox-esr, fonts, sudo, locale)…"
proot-distro login debian -- env USER_NAME="$USER_NAME" USER_PASS="$USER_PASS" bash -lc '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  apt update
  apt install -y xfce4 xfce4-goodies dbus-x11 x11-apps \
                 firefox-esr thunar thunar-archive-plugin p7zip-full \
                 pulseaudio-utils fonts-dejavu fonts-noto fonts-noto-cjk \
                 mousepad vlc sudo locales
  mkdir -p /dev/shm && chmod 1777 /dev/shm

  if ! id -u "$USER_NAME" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "$USER_NAME"
  fi
  echo "$USER_NAME:$USER_PASS" | chpasswd
  usermod -aG sudo "$USER_NAME"

  # Sudo NOPASSWD (đổi thành "ALL" nếu muốn yêu cầu mật khẩu)
  echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/99-$USER_NAME"
  chmod 0440 "/etc/sudoers.d/99-$USER_NAME"

  # locale cơ bản
  sed -i "s/^# *en_US.UTF-8/en_US.UTF-8/" /etc/locale.gen || true
  locale-gen en_US.UTF-8 || true
  update-locale LANG=en_US.UTF-8 || true
'

# 5) Tạo launcher ngắn (dx)
say "Tạo launcher ~/${LAUNCHER_NAME}…"

LAUNCH_PATH="$HOME/${LAUNCHER_NAME}"
BIN_LOCAL="$HOME/.local/bin/${LAUNCHER_NAME}"
BIN_PREFIX="$PREFIX/bin/${LAUNCHER_NAME}"

mkdir -p "$HOME/.local/bin" || true

cat > "$LAUNCH_PATH" <<'EOF_LAUNCH'
#!/data/data/com.termux/files/usr/bin/bash
# Launcher Debian XFCE qua Termux X11 (không VNC) – ngắn gọn
set -euo pipefail

say()  { printf "\033[1;32m[*]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }

CFG="$HOME/.debian-x11.conf"; [ -f "$CFG" ] && . "$CFG"
: "${USER_NAME:=droid}"

# 1) PulseAudio
if ! pgrep -x pulseaudio >/dev/null 2>&1; then
  say "Khởi động PulseAudio…"
  pulseaudio --start \
    --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 listen=127.0.0.1" \
    --exit-idle-time=-1
fi

# 2) (tùy chọn) virgl
if command -v virgl_test_server_android >/dev/null 2>&1 && \
   ! pgrep -f virgl_test_server_android >/dev/null 2>&1; then
  say "Bật virgl (tăng tốc 3D)…"
  nohup virgl_test_server_android >/dev/null 2>&1 &
  sleep 0.2
fi

export DISPLAY=:0
export PULSE_SERVER=127.0.0.1
# Nếu app 3D lỗi, comment 2 dòng dưới:
export MESA_GL_VERSION_OVERRIDE=4.5
export GALLIUM_DRIVER=virpipe

# 3) termux-x11 helper
command -v termux-x11 >/dev/null 2>&1 || { echo "[x] Thiếu termux-x11. Chạy: pkg install x11-repo termux-x11"; exit 1; }

# Nếu socket chưa có, dựng bridge :0
if ! { [ -S "$PREFIX/var/run/X11-unix/X0" ] || [ -S "$PREFIX/tmp/.X11-unix/X0" ]; }; then
  warn "Khởi chạy bridge: termux-x11 :0 (hãy mở app Termux X11 – màn đen)…"
  ( termux-x11 :0 >/dev/null 2>&1 & )
fi

# 4) Dò socket trong Termux
CANDIDATES=(
  "$PREFIX/var/run/X11-unix"
  "$PREFIX/tmp/.X11-unix"
)
SOCK_DIR=""
for _ in {1..100}; do
  for d in "${CANDIDATES[@]}"; do
    if [ -S "$d/X0" ] || { [ -d "$d" ] && ls "$d"/X* >/dev/null 2>&1; }; then
      SOCK_DIR="$d"; break
    fi
  done
  [ -n "$SOCK_DIR" ] && break
  sleep 0.1
done
[ -n "$SOCK_DIR" ] || { echo "[x] Không tìm thấy socket X11 trong Termux."; exit 1; }
say "Socket X11: $SOCK_DIR"

# 5) startxfce4 đã có chưa?
if ! proot-distro login debian -- bash -lc 'command -v startxfce4 >/dev/null 2>&1'; then
  echo "[x] Thiếu startxfce4. Hãy chạy lại install.sh."
  exit 1
fi

# 6) Vào Debian (user thường) & chạy XFCE
proot-distro login debian \
  --user "$USER_NAME" \
  --bind "$PREFIX/tmp:/tmp" \
  --bind "$SOCK_DIR:/tmp/.X11-unix" \
  --bind "$PREFIX/tmp:/dev/shm" \
  -- env -u WAYLAND_DISPLAY \
     DISPLAY=":0" PULSE_SERVER="$PULSE_SERVER" XAUTHORITY= \
     dbus-launch startxfce4
EOF_LAUNCH

chmod +x "$LAUNCH_PATH"

# 6) Lưu user cho launcher + tạo symlink tiện dụng
printf 'USER_NAME=%s\n' "$USER_NAME" > "$HOME/.debian-x11.conf"

# ~/.local/bin/dx
ln -sf "$LAUNCH_PATH" "$BIN_LOCAL"
# $PREFIX/bin/dx (nằm trong PATH mặc định)
ln -sf "$LAUNCH_PATH" "$BIN_PREFIX" 2>/dev/null || true

say "Hoàn tất!"
printf "\n👉 Khởi động nhanh desktop: \033[1m%s\033[0m\n" "$LAUNCHER_NAME"
printf "   (Bạn có thể gõ: \033[1m%s\033[0m ở bất kỳ đâu trong Termux)\n" "$LAUNCHER_NAME"# 5) Nhắc mở Termux X11
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
say "Cài đặt lệnh tiện ích X11 & launcher…"
mkdir -p "$HOME/.local/bin"
touch "$HOME/.debian-x11.conf"
printf 'USER_NAME=%s\n' "$USER_NAME" > "$HOME/.debian-x11.conf"

# --- x11-start ---
cat > "$PREFIX/bin/x11-start" <<"EOS"
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
say(){ printf "\033[1;32m[*]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err(){ printf "\033[1;31m[x]\033[0m %s\n" "$*"; }

command -v termux-x11 >/dev/null 2>&1 || { err "Thiếu 'termux-x11'. Chạy: pkg install x11-repo termux-x11"; exit 1; }

# tạo thư mục socket nếu thiếu
mkdir -p "$PREFIX/var/run/X11-unix" "$PREFIX/tmp/.X11-unix"

# khởi bridge nếu socket chưa có
if ! { [ -S "$PREFIX/var/run/X11-unix/X0" ] || [ -S "$PREFIX/tmp/.X11-unix/X0" ]; }; then
  warn "Mở app Termux X11 (màn đen) nếu chưa mở. Khởi bridge :0…"
  ( termux-x11 :0 >/dev/null 2>&1 & )
fi

# đợi socket
for _ in {1..120}; do
  if [ -S "$PREFIX/var/run/X11-unix/X0" ] || [ -S "$PREFIX/tmp/.X11-unix/X0" ]; then
    say "X11 sẵn sàng."
    exit 0
  fi
  sleep 0.1
done
err "Không thấy socket X11. Hãy đảm bảo app Termux X11 đang mở."
EOS
chmod +x "$PREFIX/bin/x11-start"

# --- x11-stop ---
cat > "$PREFIX/bin/x11-stop" <<"EOS"
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
say(){ printf "\033[1;32m[*]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[!]\033[0m %s\n" "$*"; }

# tắt bridge & virgl
pkill -f termux-x11 >/dev/null 2>&1 || true
pkill -f virgl_test_server_android >/dev/null 2>&1 || true
# optional: ép dừng app Termux X11 (nếu máy cho phép)
command -v am >/dev/null 2>&1 && am force-stop com.termux.x11 >/dev/null 2>&1 || true

say "Đã dừng bridge X11. (Không xoá socket để lần sau khởi nhanh.)"
EOS
chmod +x "$PREFIX/bin/x11-stop"

# --- x11-reset (cấp cứu) ---
cat > "$PREFIX/bin/x11-reset" <<"EOS"
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
say(){ printf "\033[1;32m[*]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err(){ printf "\033[1;31m[x]\033[0m %s\n" "$*"; }

pkill -f termux-x11 >/dev/null 2>&1 || true
pkill -f virgl_test_server_android >/dev/null 2>&1 || true
command -v am >/dev/null 2>&1 && am force-stop com.termux.x11 >/dev/null 2>&1 || true

rm -rf "$PREFIX/var/run/X11-unix" "$PREFIX/tmp/.X11-unix"
mkdir -p "$PREFIX/var/run/X11-unix" "$PREFIX/tmp/.X11-unix"

warn "Mở app Termux X11 (màn đen)… khởi bridge :0"
( termux-x11 :0 >/dev/null 2>&1 & )

for _ in {1..120}; do
  if [ -S "$PREFIX/var/run/X11-unix/X0" ] || [ -S "$PREFIX/tmp/.X11-unix/X0" ]; then
    say "X11 đã reset xong."
    exit 0
  fi
  sleep 0.1
done
err "Reset không thành công. Hãy mở app Termux X11 rồi chạy lại."
EOS
chmod +x "$PREFIX/bin/x11-reset"

# --- dx (launcher desktop) ---
cat > "$PREFIX/bin/dx" <<"EOS"
#!/data/data/com.termux/files/usr/bin/bash
# Desktop launcher (Debian XFCE qua Termux X11)
set -euo pipefail
say(){ printf "\033[1;32m[*]\033[0m %s\n" "$*"; }
err(){ printf "\033[1;31m[x]\033[0m %s\n" "$*"; }

CFG="$HOME/.debian-x11.conf"; [ -f "$CFG" ] && . "$CFG"
: "${USER_NAME:=droid}"

export DISPLAY=:0
export PULSE_SERVER=127.0.0.1
# comment 2 dòng dưới nếu 3D lỗi
export MESA_GL_VERSION_OVERRIDE=4.5
export GALLIUM_DRIVER=virpipe

# đảm bảo pulseaudio
pgrep -x pulseaudio >/dev/null 2>&1 || pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 listen=127.0.0.1" --exit-idle-time=-1

# virgl (tuỳ chọn)
if command -v virgl_test_server_android >/dev/null 2>&1 && ! pgrep -f virgl_test_server_android >/dev/null 2>&1; then
  nohup virgl_test_server_android >/dev/null 2>&1 &
fi

# bật X11
x11-start

# chọn socket (ưu tiên var/run)
SOCK_DIR=""
if [ -S "$PREFIX/var/run/X11-unix/X0" ]; then
  SOCK_DIR="$PREFIX/var/run/X11-unix"
elif [ -S "$PREFIX/tmp/.X11-unix/X0" ]; then
  SOCK_DIR="$PREFIX/tmp/.X11-unix"
else
  err "Không tìm thấy socket X11 sau khi x11-start."
fi
say "Socket X11: $SOCK_DIR"

# chắc chắn có startxfce4
if ! proot-distro login debian -- bash -lc 'command -v startxfce4 >/dev/null 2>&1'; then
  err "Thiếu startxfce4. Chạy lại install.sh."
fi

# vào Debian & chạy XFCE
exec proot-distro login debian \
  --user "$USER_NAME" \
  --bind "$PREFIX/tmp:/tmp" \
  --bind "$SOCK_DIR:/tmp/.X11-unix" \
  --bind "$PREFIX/tmp:/dev/shm" \
  -- env -u WAYLAND_DISPLAY \
     DISPLAY=":0" PULSE_SERVER="$PULSE_SERVER" XAUTHORITY= \
     dbus-launch startxfce4
EOS
chmod +x "$PREFIX/bin/dx"

say "Đã cài lệnh: dx, x11-start, x11-stop, x11-reset (có trong PATH)."
