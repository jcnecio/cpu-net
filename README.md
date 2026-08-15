# System & Network (`cpu-net`)

A `bar-widget` plugin for the Omarchy Quattro shell (Quickshell). Shows CPU,
GPU, and memory percentages plus live network speed in the bar, with a details
panel covering swap, disk, top processes, and network traffic.

Built from the waybar-era `net_speed.sh` and `system_info.py` scripts: same
data sources (`/proc/net/dev`, `ping`, `nvidia-smi`/`rocm-smi`, `/proc/*`),
now emitting clean JSON that the Quickshell UI renders natively.

<img width="392" height="892" alt="screenshot-2026-08-15_18-15-10" src="https://github.com/user-attachments/assets/748f210b-7b6e-4a2f-8e55-a8b445dc3d86" />

## Install

```sh
# From this repository
mkdir -p ~/.config/omarchy/plugins
cp -r cpu-net ~/.config/omarchy/plugins/
omarchy-shell shell rescanPlugins
omarchy plugin enable cpu-net
omarchy bar move cpu-net --section right
```

## Usage

- **Left click** toggles the details panel.
- **Right click** forces an immediate refresh.
- **Escape** closes the panel; **Tab** switches to the adjacent panel.
- `omarchy-shell shell summon cpu-net '{}'` opens it via IPC.

## Configure

Polling interval (ms) is tunable per-widget in `~/.config/omarchy/shell.json`:

```json
{ "id": "cpu-net", "interval": 2500 }
```

## Data sources

- `system_info.py` — pure Python stdlib: `/proc/stat` (CPU), `/proc/meminfo`
  (RAM/swap), `shutil.disk_usage` (disk), `/proc/[pid]/statm` (top processes),
  `/proc/uptime`, and `nvidia-smi` / `rocm-smi` for the GPU when present.
- `net_speed.sh` — `ip route get` for the interface, `/proc/net/dev` deltas for
  download/upload, `ping` for latency. No `bc`.

## Dependencies

None. No `bc`, no `psutil`, no third-party Python packages. The only optional
tooling is `nvidia-smi` (NVIDIA) or `rocm-smi` (AMD) for GPU metrics.

## Remove

```sh
omarchy plugin remove cpu-net
```

## License

MIT — see [LICENSE](LICENSE).
