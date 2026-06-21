#!/usr/bin/env python3
"""Minimal Source RCON client used by the Minenux Minecraft management scripts.

Minecraft's RCON implementation is the same wire protocol as Source-engine
games (packet types 3=AUTH, 2=AUTH_RESPONSE/EXECCOMMAND, 0=RESPONSE_VALUE).
No third-party dependency required - pure stdlib socket + struct.
"""
import socket
import struct
import sys
import time


def pack_packet(req_id: int, pkt_type: int, body: str) -> bytes:
    payload = struct.pack('<ii', req_id, pkt_type) + body.encode('utf-8') + b'\x00\x00'
    return struct.pack('<i', len(payload)) + payload


def read_packet(sock: socket.socket):
    raw_len = sock.recv(4)
    if len(raw_len) < 4:
        raise ConnectionError("connection closed by server")
    length = struct.unpack('<i', raw_len)[0]
    data = b''
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            raise ConnectionError("connection closed mid-packet")
        data += chunk
    req_id, pkt_type = struct.unpack('<ii', data[:8])
    body = data[8:-2].decode('utf-8', errors='replace')
    return req_id, pkt_type, body


def run(host: str, port: int, password: str, commands, retries: int, retry_delay: int):
    last_err = None
    for _ in range(retries):
        try:
            with socket.create_connection((host, port), timeout=5) as sock:
                sock.sendall(pack_packet(1, 3, password))
                req_id, _, _ = read_packet(sock)
                if req_id == -1:
                    raise PermissionError("RCON authentication failed (wrong password)")
                outputs = []
                for i, cmd in enumerate(commands, start=2):
                    sock.sendall(pack_packet(i, 2, cmd))
                    _, _, body = read_packet(sock)
                    outputs.append(body)
                return outputs
        except PermissionError:
            raise
        except Exception as e:  # connection refused / timeout / server still booting
            last_err = e
            time.sleep(retry_delay)
    raise ConnectionError(f"could not reach RCON at {host}:{port} ({last_err})")


if __name__ == '__main__':
    args = sys.argv[1:]
    wait = False
    if args and args[0] == '--wait':
        wait = True
        args = args[1:]

    if len(args) < 4:
        print("Usage: rcon.py [--wait] <host> <port> <password> <command1> [command2 ...]", file=sys.stderr)
        sys.exit(1)

    host, port_s, password = args[0], args[1], args[2]
    commands = args[3:]
    retries, delay = (40, 3) if wait else (1, 1)  # --wait: up to ~2min for world-gen boot

    try:
        results = run(host, int(port_s), password, commands, retries, delay)
        for cmd, out in zip(commands, results):
            print(f"[{cmd}] -> {out}")
    except Exception as e:
        print(f"RCON ERROR: {e}", file=sys.stderr)
        sys.exit(2)
