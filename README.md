# Debian X11 cho Termux

Repo này giúp bạn cài Debian + XFCE + Firefox với âm thanh,
chạy trực tiếp qua Termux X11 (không dùng VNC).

## Cài đặt
- Tải và cài đặt Termux[Termux](https://termux.com) apk [Đây](https://f-droid.org/repo/com.termux_118.apk)

Dán lệnh vào Termux:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DinhQuangDoi/debian-termux-x11/main/install.sh)
```
Script sẽ:

Cài gói cần thiết trong Termux

Cài Debian (nếu chưa có)

Cấu hình XFCE, Firefox, âm thanh, fonts

Tạo user thường + sudo

Tạo lệnh khởi động ngắn gọn


Khởi động & Tắt nhanh

Khởi động desktop
Mở app Termux X11 (màn hình đen), rồi trong Termux gõ:
```
dx
```
→ Vào ngay Debian XFCE (âm thanh + trình duyệt sẵn).

Tắt bridge X11 (không xoá socket, lần sau vào nhanh):
```
x11-stop
```
Reset X11 khi bị kẹt/đen màn:
(xử lý khi kill app Termux X11 hoặc socket lỗi)
```
x11-reset
dx
```
> 💡 Trong Debian, để thoát phiên làm việc sạch sẽ, gõ:
```
xfce4-session-logout --logout
```


Mẹo & ghi chú

Nếu ứng dụng 3D bị lỗi → mở ~/.debian-x11.conf và comment 2 dòng:
```
# export MESA_GL_VERSION_OVERRIDE=4.5
# export GALLIUM_DRIVER=virpipe
```
Âm thanh không ra? Trong Debian kiểm tra:
```
pactl info

Nếu Server String khác 127.0.0.1, chạy:

export PULSE_SERVER=127.0.0.1
```
Font đầy đủ cho tiếng Việt, CJK đã cài sẵn (fonts-noto-*).


