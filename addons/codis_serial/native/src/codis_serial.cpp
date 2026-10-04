#include "codis_serial.h"

#include <godot_cpp/core/class_db.hpp>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <fcntl.h>
#include <termios.h>
#include <unistd.h>
#include <dirent.h>
#include <cstring>
#include <cerrno>
#endif

using namespace godot;

CodisSerial::CodisSerial() {}
CodisSerial::~CodisSerial() { close(); }

void CodisSerial::_bind_methods() {
	ClassDB::bind_method(D_METHOD("list_ports"), &CodisSerial::list_ports);
	ClassDB::bind_method(D_METHOD("open", "port", "baud"), &CodisSerial::open, DEFVAL(115200));
	ClassDB::bind_method(D_METHOD("write", "data"), &CodisSerial::write);
	ClassDB::bind_method(D_METHOD("read", "max_bytes"), &CodisSerial::read, DEFVAL(1024));
	ClassDB::bind_method(D_METHOD("close"), &CodisSerial::close);
	ClassDB::bind_method(D_METHOD("is_open"), &CodisSerial::is_open);
	ClassDB::bind_method(D_METHOD("flash", "fqbn", "port", "payload"), &CodisSerial::flash);
}

bool CodisSerial::is_open() const { return _fd >= 0; }

PackedStringArray CodisSerial::list_ports() const {
	PackedStringArray out;
#ifdef _WIN32
	for (int i = 1; i <= 256; i++) {
		char name[32];
		snprintf(name, sizeof(name), "\\\\.\\COM%d", i);
		HANDLE h = CreateFileA(name, GENERIC_READ | GENERIC_WRITE, 0, nullptr,
				OPEN_EXISTING, 0, nullptr);
		if (h != INVALID_HANDLE_VALUE) {
			CloseHandle(h);
			char label[16];
			snprintf(label, sizeof(label), "COM%d", i);
			out.push_back(String(label));
		}
	}
#else
	// Linux / macOS / Android (with a rooted USB-serial driver).
	DIR *dir = opendir("/dev");
	if (dir) {
		struct dirent *e;
		while ((e = readdir(dir)) != nullptr) {
			String n(e->d_name);
			if (n.begins_with("ttyUSB") || n.begins_with("ttyACM") ||
					n.begins_with("ttyS") || n.begins_with("cu.")) {
				out.push_back(String("/dev/") + n);
			}
		}
		closedir(dir);
	}
#endif
	return out;
}

bool CodisSerial::open(const String &p_port, int p_baud) {
	close();
	_baud = p_baud;
#ifdef _WIN32
	String path = p_port;
	if (!path.begins_with("\\\\.\\")) {
		path = String("\\\\.\\") + p_port;
	}
	HANDLE h = CreateFileA(path.utf8().get_data(), GENERIC_READ | GENERIC_WRITE,
			0, nullptr, OPEN_EXISTING, 0, nullptr);
	if (h == INVALID_HANDLE_VALUE) {
		return false;
	}
	DCB dcb = {};
	dcb.DCBlength = sizeof(dcb);
	if (!GetCommState(h, &dcb)) {
		CloseHandle(h);
		return false;
	}
	dcb.BaudRate = (DWORD)p_baud;
	dcb.ByteSize = 8;
	dcb.StopBits = ONESTOPBIT;
	dcb.Parity = NOPARITY;
	SetCommState(h, &dcb);
	_fd = (intptr_t)h;
#else
	int fd = ::open(p_port.utf8().get_data(), O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (fd < 0) {
		return false;
	}
	struct termios tty;
	memset(&tty, 0, sizeof(tty));
	if (tcgetattr(fd, &tty) != 0) {
		::close(fd);
		return false;
	}
	speed_t speed = B115200;
	switch (p_baud) {
		case 9600: speed = B9600; break;
		case 19200: speed = B19200; break;
		case 38400: speed = B38400; break;
		case 57600: speed = B57600; break;
		case 115200: speed = B115200; break;
		case 230400: speed = B230400; break;
		default: speed = B115200; break;
	}
	cfsetospeed(&tty, speed);
	cfsetispeed(&tty, speed);
	tty.c_cflag = (tty.c_cflag & ~CSIZE) | CS8;
	tty.c_cflag |= (CLOCAL | CREAD);
	tty.c_cflag &= ~(PARENB | PARODD);
	tty.c_cflag &= ~CSTOPB;
	tty.c_cflag &= ~CRTSCTS;
	tty.c_lflag = 0;
	tty.c_iflag = 0;
	tty.c_oflag = 0;
	tty.c_cc[VMIN] = 0;
	tty.c_cc[VTIME] = 5;
	tcsetattr(fd, TCSANOW, &tty);
	_fd = fd;
#endif
	return true;
}

int CodisSerial::write(const PackedByteArray &p_data) {
	if (_fd < 0) {
		return -1;
	}
	int total = 0;
	const uint8_t *ptr = p_data.ptr();
	int remaining = p_data.size();
#ifdef _WIN32
	HANDLE h = (HANDLE)(intptr_t)_fd;
	DWORD written = 0;
	while (remaining > 0) {
		if (!WriteFile(h, ptr, (DWORD)remaining, &written, nullptr)) {
			break;
		}
		if (written == 0) {
			break;
		}
		ptr += written;
		remaining -= (int)written;
		total += (int)written;
	}
#else
	while (remaining > 0) {
		ssize_t n = ::write(_fd, ptr, (size_t)remaining);
		if (n <= 0) {
			break;
		}
		ptr += n;
		remaining -= (int)n;
		total += (int)n;
	}
#endif
	return total;
}

PackedByteArray CodisSerial::read(int p_max_bytes) {
	PackedByteArray out;
	if (_fd < 0 || p_max_bytes <= 0) {
		return out;
	}
	PackedByteArray buf;
	buf.resize(p_max_bytes);
#ifdef _WIN32
	HANDLE h = (HANDLE)(intptr_t)_fd;
	DWORD got = 0;
	if (ReadFile(h, buf.ptrw(), (DWORD)p_max_bytes, &got, nullptr) && got > 0) {
		out = buf.slice(0, (int)got);
	}
#else
	ssize_t n = ::read(_fd, buf.ptrw(), (size_t)p_max_bytes);
	if (n > 0) {
		out = buf.slice(0, (int)n);
	}
#endif
	return out;
}

void CodisSerial::close() {
	if (_fd < 0) {
		return;
	}
#ifdef _WIN32
	CloseHandle((HANDLE)(intptr_t)_fd);
#else
	::close(_fd);
#endif
	_fd = -1;
}

bool CodisSerial::flash(const String &p_fqbn, const String &p_port, const PackedByteArray &p_payload) {
	// Implement the bootloader handshake for the target architecture here:
	//   * AVR boards  -> STK500 / avrdude "arduino" protocol (DTR reset + sync).
	//   * ESP boards  -> esptool SLIP protocol.
	//   * Boards whose payload is already a serial script -> raw write.
	//
	// The GDScript side already compiled (desktop) or received (BT/OTA) the
	// payload; this is where it reaches the chip. The default below performs a
	// best-effort raw write, which is enough for serial bootloaders that accept
	// the image verbatim.
	if (!open(p_port)) {
		return false;
	}
	bool ok = write(p_payload) == p_payload.size();
	close();
	return ok;
}
