#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "[*] Cập nhật Termux..."
pkg update -y && pkg upgrade -y
pkg install -y x11-repo proot-distro pulseaudio virglrenderer-android

echo "[*] Cài Debian..."
proot-distro install debian || true

echo "[*] Copy script cấu hình..."
curl -fsSL https://raw.githubusercontent.com/DinhQuangDoi/debian-termux-x11/main/debian-x11.sh \
  -o ~/.debian-x11.sh
chmod +x ~/.debian-x11.sh

echo "[*] Tạo lệnh start-debian-x11..."
cat > ~/start-debian-x11 <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -e
# Khởi động PulseAudio
if ! pgrep -x pulseaudio >/dev/null 2>&1; then
  pulseaudio --start \
    --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 listen=127.0.0.1" \
    --exit-idle-time=-1
fi

# Bật virgl tăng tốc (nếu có)
if command -v virgl_test_server_android >/dev/null 2>&1; then
  if ! pgrep -f virgl_test_server_android >/dev/null 2>&1; then
    nohup virgl_test_server_android >/dev/null 2>&1 &
  fi
fi

export DISPLAY=:0
export PULSE_SERVER=127.0.0.1
export MESA_GL_VERSION_OVERRIDE=4.5
export GALLIUM_DRIVER=virpipe

# Bind X11 socket và shm
proot-distro login debian --bind $PREFIX/tmp:/tmp --bind /dev/shm:/dev/shm -- \
  env -u WAYLAND_DISPLAY DISPLAY=$DISPLAY PULSE_SERVER=$PULSE_SERVER \
  dbus-launch startxfce4
EOF
chmod +x ~/start-debian-x11

echo
echo "[*] Hoàn tất!"
echo "👉 Bước tiếp theo:"
echo "  1. Cài ứng dụng Termux X11 nếu chưa có (APK)."
echo "  2. Mở app Termux X11 (màn đen)."
echo "  3. Quay lại Termux và chạy: ~/start-debian-x11"
