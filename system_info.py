#!/usr/bin/env python3
"""System diagnostics for the cpu-net Quickshell bar widget.

Pure Python stdlib: no psutil, no third-party packages. Reads /proc and
probes nvidia-smi / rocm-smi when present. Emits clean JSON:

{
  "cpu": 32,                  # int percent
  "gpu": 50,                  # int percent or null when unavailable
  "gpuName": "NVIDIA ...",    # string or "" when unavailable
  "gpuMemUsed": null,         # bytes or null
  "gpuMemTotal": null,        # bytes or null
  "memPercent": 45,           # int
  "memUsed": 123,             # bytes
  "memTotal": 456,            # bytes
  "memAvailable": 456,        # bytes
  "swapPercent": 12,          # int
  "diskPercent": 60,          # int
  "diskUsed": 123,            # bytes
  "diskTotal": 456,           # bytes
  "processes": [["chrome", 123], ...],  # top 8 by RSS, [name, rss bytes]
  "uptime": "2 hours, 5 minutes"
}
"""

import json
import os
import re
import shutil
import subprocess
import time

CLK = os.sysconf("SC_CLK_TCK")
PAGE_SIZE = os.sysconf("SC_PAGE_SIZE")


def fmt_bytes(value):
    """Match psutil's human-readable formatting for fallback labels."""
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if value < 1024:
            return "%.1f%s" % (value, unit)
        value /= 1024
    return "%.1fPB" % value


def cpu_percent(interval=1.0):
    """Recent CPU utilization from /proc/stat, sampled over `interval`."""
    def sample():
        with open("/proc/stat", "r") as f:
            fields = f.readline().split()
        nums = [int(x) for x in fields[1:8]]  # user nice system idle iowait irq softirq
        idle = nums[3] + nums[4]
        return sum(nums), idle

    total1, idle1 = sample()
    time.sleep(interval)
    total2, idle2 = sample()
    dt = total2 - total1
    if dt <= 0:
        return 0.0
    return max(0.0, min(100.0, 100.0 * (1.0 - (idle2 - idle1) / dt)))


def meminfo():
    """Parsed /proc/meminfo as {key: bytes-or-int}."""
    data = {}
    with open("/proc/meminfo", "r") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2:
                data[parts[0].rstrip(":")] = int(parts[1]) * 1024  # kB -> bytes
    return data


def memory_stats():
    """RAM: percent, used, available, total (bytes)."""
    info = meminfo()
    total = info.get("MemTotal", 0)
    available = info.get("MemAvailable", info.get("MemFree", 0))
    used = max(0, total - available)
    percent = (used / total * 100) if total > 0 else 0
    return int(percent), used, available, total


def swap_stats():
    """Swap percent."""
    info = meminfo()
    total = info.get("SwapTotal", 0)
    free = info.get("SwapFree", 0)
    used = max(0, total - free)
    percent = (used / total * 100) if total > 0 else 0
    return int(percent)


def disk_stats():
    """Disk percent, used, total (bytes) for the root mount."""
    usage = shutil.disk_usage("/")
    percent = (usage.used / usage.total * 100) if usage.total > 0 else 0
    return int(percent), usage.used, usage.total


def top_processes(limit=8):
    """Top `limit` processes by RSS from /proc/<pid>/statm."""
    procs = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = entry
        try:
            with open("/proc/%s/statm" % pid, "r") as f:
                fields = f.read().split()
            with open("/proc/%s/comm" % pid, "r") as f:
                name = f.read().strip()
            if len(fields) < 2:
                continue
            rss = int(fields[1]) * PAGE_SIZE
            procs.append((name, rss))
        except (OSError, ValueError):
            continue
    procs.sort(key=lambda x: x[1], reverse=True)
    return procs[:limit]


def get_gpu_info():
    """GPU usage, name, mem (bytes) via nvidia-smi or rocm-smi. None when absent."""
    # NVIDIA first (most common).
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,name",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=2)
        if result.returncode == 0:
            parts = [p.strip() for p in result.stdout.strip().split(",")]
            if len(parts) >= 4 and parts[0].isdigit():
                return (int(parts[0]), parts[3].strip(),
                        int(parts[1]) * 1024 * 1024, int(parts[2]) * 1024 * 1024)
    except (subprocess.TimeoutExpired, FileNotFoundError, subprocess.SubprocessError):
        pass

    # AMD ROCm.
    try:
        result = subprocess.run(
            ["rocm-smi", "--showuse", "--showmemuse", "--showproductname"],
            capture_output=True, text=True, timeout=2)
        if result.returncode == 0:
            usage = None
            name = ""
            for line in result.stdout.splitlines():
                m = re.search(r"(\d+)%", line)
                if ("GPU use" in line or "GPU Utilization" in line) and m:
                    usage = int(m.group(1))
                elif ("Card series" in line or "Product Name" in line) and ":" in line:
                    name = line.split(":", 1)[1].strip()
            if usage is not None:
                return (usage, name, None, None)
    except (subprocess.TimeoutExpired, FileNotFoundError, subprocess.SubprocessError):
        pass

    return None, "", None, None


def uptime_string():
    """Human uptime like `uptime -p`: '2 hours, 5 minutes'."""
    try:
        with open("/proc/uptime", "r") as f:
            secs = float(f.read().split()[0])
    except (OSError, ValueError):
        return "unknown"
    days = int(secs // 86400)
    hours = int((secs % 86400) // 3600)
    mins = int((secs % 3600) // 60)
    parts = []
    if days:
        parts.append("1 day" if days == 1 else "%d days" % days)
    if hours:
        parts.append("1 hour" if hours == 1 else "%d hours" % hours)
    if mins:
        parts.append("1 minute" if mins == 1 else "%d minutes" % mins)
    if not parts:
        parts.append("0 minutes")
    return ", ".join(parts)


def get_sys_info():
    gpu_usage, gpu_name, gpu_mem_used, gpu_mem_total = get_gpu_info()
    mem_percent, mem_used, mem_available, mem_total = memory_stats()

    return json.dumps({
        "cpu": int(cpu_percent(1.0)),
        "gpu": gpu_usage,
        "gpuName": gpu_name or "",
        "gpuMemUsed": gpu_mem_used,
        "gpuMemTotal": gpu_mem_total,
        "memPercent": mem_percent,
        "memUsed": mem_used,
        "memTotal": mem_total,
        "memAvailable": mem_available,
        "swapPercent": swap_stats(),
        "diskPercent": disk_stats()[0],
        "diskUsed": disk_stats()[1],
        "diskTotal": disk_stats()[2],
        "processes": top_processes(8),
        "uptime": uptime_string(),
    })


if __name__ == "__main__":
    print(get_sys_info())
