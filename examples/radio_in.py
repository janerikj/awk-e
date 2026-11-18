#!/usr/bin/env python3
'''
Connects to Direwolf on TCP port 8001 to receive incoming radio packets sent using
the KISS protocol. It decodes the raw binary KISS and AX.25 frames into plain
text and outputs each message line-by-line formatted for awk-e:
 "radio/in/<freq>/<src>/<dest> <message>"
'''
import socket
import sys
import time

HOST = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8001

FREQ = "69mhz"

def decode_call(b: bytes) -> str:
    name = "".join(chr(x >> 1) for x in b[:6]).strip()
    ssid = (b >> 1) & 0x0F
    return f"{name}-{ssid}" if ssid else name

def parse_kiss(frame: bytearray) -> str | None:
    # Handle KISS byte-stuffing (DB DC -> C0, DB DD -> DB)
    raw = bytearray()
    i = 0
    while i < len(frame):
        if frame[i] == 0xDB and i + 1 < len(frame):
            raw.append(0xC0 if frame[i + 1] == 0xDC else 0xDB)
            i += 2
        else:
            raw.append(frame[i])
            i += 1

    # Require atleast 1 byte port + 14 bytes addresses + 2 bytes control/pid
    if len(raw) < 17 or (raw & 0x0F) != 0:
        return None

    ax = raw[1:]
    dest = decode_call(ax[0:7])
    src = decode_call(ax[7:14])

    # Skip any digipeaters until last address byte (bit 0 == 1)
    idx = 14
    while idx < len(ax) and not (ax[idx - 1] & 0x01):
        idx += 7

    if idx + 2 >= len(ax):
        return None

    msg = ax[idx + 2:].decode("utf-8", errors="replace")
    msg = msg.replace("\r", " ").replace("\n", " ").strip()
    return f"radio/in/{FREQ}/{src}/{dest} {msg}"

def main():
    while True:
        try:
            with socket.create_connection((HOST, PORT), timeout=10) as sock:
                sock.settimeout(None)
                buf = bytearray()
                while True:
                    chunk = sock.recv(1024)
                    if not chunk:
                        break
                    buf.extend(chunk)
                    while b"\xc0" in buf:
                        frame, _, buf = buf.partition(b"\xc0")
                        if frame:
                            line = parse_kiss(frame)
                            if line:
                                print(line, flush=True)
        except (OSError, ConnectionError):
            # Wait 3 seconds and try again if Direwolf has not started yet
            time.sleep(3)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
