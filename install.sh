#!/data/data/com.termux/files/usr/bin/bash
# install.sh – Termux → Debian XFCE qua Termux X11 (không VNC)
set -euo pipefail

say() { printf "\033[1;32m[*]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }

# 0) Tiền đề
if [ -z "${PREFIX:-}" ] || [ ! -d "$PREFIX" ]; then
  err "Đây không phải môi trường Termux. Hãy chạy script trong Termux."
  exit 1
fi

# 1) Cập nhật & cài gói Termux
say "Cập nhật Termux & cài gói cần thiết…"
pkg update -y && pkg upgrade -y
pkg install -y x11-repo proot-distro pulseaudio || {
  err "Không thể cài gói nền. Kiểm tra kết nối mạng?"
  exit 1
}
# Virgl là tùy chọn để tăng tốc 3D (nếu không có cũng không sao)
pkg install -y virglrenderer-android >/dev/null 2>&1 || true

# 2) Cài Debian (nếu chưa)
if ! proot-distro list | grep -q '^debian$'; then
  say "Cài Debian…"
  proot-distro install debian
else
  say "Debian đã tồn tại, bỏ qua bước cài."
fi

# 3) Chạy bootstrap bên trong Debian: cài GUI, trình duyệt, âm thanh…
say "Cấu hình Debian (cài XFCE, dbus-x11, firefox-esr, fonts, v.v.)…"
proot-distro login debian -- bash -lc '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  apt update
  apt install -y xfce4 xfce4-goodies dbus-x11 x11-apps \
                 firefox-esr thunar thunar-archive-plugin p7zip-full \
                 pulseaudio-utils fonts-dejavu fonts-noto fonts-noto-cjk \
                 mousepad vlc
  mkdir -p /dev/shm && chmod 1777 /dev/shm
'

# 4) Tạo launcher ~/start-debian-x11 (idempotent)
say "Tạo launcher ~/start-debian-x11…"
cat > "$HOME/start-debian-x11" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

say() { printf "\033[1;32m[*]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }

# 1) Khởi động PulseAudio nếu chưa chạy (TCP localhost)
if ! pgrep -x pulseaudio >/dev/null 2>&1; then
  say "Khởi động PulseAudio…"
  pulseaudio --start \
    --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 listen=127.0.0.1" \
    --exit-idle-time=-1
fi

# 2) (Tùy chọn) Bật virgl để tăng tốc OpenGL cho Termux X11
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
# Bật virpipe nếu có (không bắt buộc; nếu app 3D lỗi có thể comment 2 dòng dưới)
export MESA_GL_VERSION_OVERRIDE=4.5
export GALLIUM_DRIVER=virpipe

# 4) Kiểm tra startxfce4 tồn tại trong Debian
if ! proot-distro login debian -- bash -lc 'command -v startxfce4 >/dev/null 2>&1'; then
  err "Thiếu startxfce4. Có thể cài đặt GUI chưa hoàn tất. Chạy lại: install.sh"
  exit 1
fi

# 5) Nhắc mở app Termux X11
warn "Hãy mở ứng dụng Termux X11 (màn hình đen) trước khi tiếp tục."
sleep 1

# 6) Vào Debian & khởi động XFCE
#   - Bind $PREFIX/tmp vào /tmp để chia sẻ socket X11 (:0)
#   - Bind $PREFIX/tmp vào /dev/shm để thay thế shared memory (Android không có /dev/shm)
proot-distro login debian \
  --bind "$PREFIX/tmp:/tmp" \
  --bind "$PREFIX/tmp:/dev/shm" \
  -- env -u WAYLAND_DISPLAY \
     DISPLAY="$DISPLAY" PULSE_SERVER="$PULSE_SERVER" \
     dbus-launch startxfce4
EOF
chmod +x "$HOME/start-debian-x11"

# 5) (Tùy chọn) Tạo alias tiện lợi
if ! grep -q 'start-debian-x11' "$HOME/.bashrc" 2>/dev/null; then
  echo 'alias debian-x11="~/start-debian-x11"' >> "$HOME/.bashrc"
fi

say "Hoàn tất!"
printf "\n👉 Bước tiếp theo:\n"
printf "  1) Cài & mở ứng dụng Termux X11 nếu chưa có (APK).\n"
printf "  2) Quay lại Termux và chạy: \033[1m~/start-debian-x11\033[0m\n"
printf "     (hoặc: \033[1mdebian-x11\033[0m nếu đã mở session mới)\n"
