#!/usr/bin/env python3
"""释放 API 使用的静态文件端口与主服务端口（默认 8100 / 8200）。"""
from __future__ import annotations

import glob
import os
import re
import signal
import sys

# 与 API/config 或 utils 中端口一致
DEFAULT_PORTS = (8100, 8200)


def _listen_inodes_for_ports(ports: set[int]) -> dict[str, int]:
    """返回 inode -> port（仅 LISTEN）。"""
    inode_to_port: dict[str, int] = {}
    try:
        with open("/proc/net/tcp", encoding="utf-8") as f:
            next(f, None)
            for line in f:
                parts = line.split()
                if len(parts) < 10:
                    continue
                local, st = parts[1], parts[3]
                if st != "0A":
                    continue
                port_hex = local.rsplit(":", 1)[-1]
                port = int(port_hex, 16)
                if port not in ports:
                    continue
                inode = parts[9]
                inode_to_port[inode] = port
    except OSError as e:
        print(f"读取 /proc/net/tcp 失败: {e}", file=sys.stderr)
    return inode_to_port


def _pids_for_socket_inodes(target_inodes: set[str]) -> dict[int, list[str]]:
    """pid -> list of inode strings。"""
    found: dict[int, list[str]] = {}
    for proc in glob.glob("/proc/[0-9]*"):
        pid_s = os.path.basename(proc)
        if not pid_s.isdigit():
            continue
        pid = int(pid_s)
        fd_dir = os.path.join(proc, "fd")
        try:
            names = os.listdir(fd_dir)
        except OSError:
            continue
        for name in names:
            path = os.path.join(fd_dir, name)
            try:
                link = os.readlink(path)
            except OSError:
                continue
            m = re.match(r"socket:\[(\d+)\]", link)
            if not m:
                continue
            ino = m.group(1)
            if ino in target_inodes:
                found.setdefault(pid, []).append(ino)
    return found


def main() -> int:
    ports = {int(x) for x in (sys.argv[1:] or DEFAULT_PORTS)}
    inode_map = _listen_inodes_for_ports(ports)
    if not inode_map:
        print(f"未发现监听端口 {sorted(ports)} 的 TCP 套接字。")
        return 0

    target_inodes = set(inode_map.keys())
    pids = _pids_for_socket_inodes(target_inodes)
    if not pids:
        print(f"端口 {sorted(ports)} 有监听 inode，但未解析到进程（权限不足？）。")
        return 1

    for pid, inodes in sorted(pids.items()):
        port_hits = sorted({inode_map[i] for i in inodes if i in inode_map})
        try:
            cmdline = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\x00", b" ").decode(
                "utf-8", errors="replace"
            )[:200]
        except OSError:
            cmdline = "?"
        print(f"终止 pid={pid} 端口={port_hits} cmd={cmdline!r}")
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        except PermissionError as e:
            print(f"  无权限发送信号: {e}", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
