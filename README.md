# ESP-IDF Dockerized Development Environment

This repository provides **cross-platform wrappers** around Espressif’s official Docker images for ESP-IDF development.

With these scripts, developers can use `idf.py` as if it were installed locally — but everything runs inside a pre-configured container (`espressif/idf:release-v5.5`).  
The wrappers handle path mounting, permissions, serial ports, and WSL integration automatically.

---

## 🧰 Included Scripts

| Script | Platform | Purpose |
|--------|-----------|----------|
| `scripts/idf` | Linux & macOS | Main wrapper that runs `idf.py` commands in Docker. |
| `scripts/idf.ps1` | Windows (PowerShell) | Windows version that executes all commands through WSL2. |
| `scripts/Set-Esp32Port.ps1` | Windows (PowerShell) | Helper to attach a USB device via `usbipd` and set `ESPPORT`. |

---

## 🧩 How It Works

### Linux & macOS (`scripts/idf`)
- Runs `docker run --rm -it espressif/idf:release-v5.5 idf.py …`.
- Mounts your **current project folder** into `/workspace` inside the container.
- Maps your **UID/GID** to prevent root-owned build artifacts.
- Forwards environment variables:
  - `IDF_IMAGE` (custom Docker image tag)
  - `ESPPORT`, `ESPBAUD`
  - `IDF_GITHUB_ASSETS` (optional GitHub mirror)
- On Linux:
  - Automatically passes `/dev/ttyUSB*` and `/dev/ttyACM*` for flashing and monitoring.
- On macOS:
  - **Builds only**. Docker Desktop can’t forward USB serial devices. You can flash using `esptool.py` natively.

### Windows PowerShell (`scripts/idf.ps1`)
- Runs **everything inside WSL2**, not Docker Desktop for Windows directly.
- Converts `C:\path` → `/mnt/c/path` and runs `docker run` from within WSL.
- Auto-exports Windows environment variables (`ESPPORT`, `ESPBAUD`, `IDF_IMAGE`) into WSL before execution.
- Detects `/dev/ttyUSB*` and `/dev/ttyACM*` in WSL (after you attach the board with `usbipd`).
- All normal `idf.py` subcommands (`build`, `flash`, `monitor`, `fullclean`, etc.) work seamlessly.

### Windows USB Helper (`scripts/Set-Esp32Port.ps1`)
- Lists available USB devices with `usbipd wsl list`.
- Attaches the chosen device to your WSL distro (`usbipd wsl attach --busid …`).
- Probes inside WSL for `/dev/ttyUSB*` and sets `ESPPORT` accordingly.
- Optionally persists `ESPPORT` as a user environment variable for future sessions.

---

## 🚀 Setup

### Linux / macOS

1. Install **Docker**.
2. Copy `scripts/idf` to your PATH and make it executable:
   ```bash
   chmod +x scripts/idf
   mkdir -p ~/.local/bin
   cp scripts/idf ~/.local/bin/
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
   exec $SHELL -l
   ```
3. (Optional) Add alias for native feel:
   ```bash
   echo 'alias idf.py="idf"' >> ~/.bashrc
   ```
4. Use it:
   ```bash
   idf set-target esp32
   idf build
   idf -p /dev/ttyUSB0 flash
   idf monitor
   idf fullclean
   ```

> ⚠️ On macOS: Docker cannot forward serial ports. Build inside Docker, flash with native `esptool.py`:
> ```bash
> pip3 install --user esptool
> esptool.py --chip esp32 --port /dev/tty.usbserial-XXXX write_flash 0x10000 build/app.bin
> ```

---

### Windows (PowerShell + WSL2)

1. Install **WSL2** (Ubuntu recommended):
   ```powershell
   wsl --install -d Ubuntu
   ```
2. Install **Docker** inside WSL or enable Docker Desktop’s **WSL integration**.
3. Install **usbipd** for USB passthrough:
   ```powershell
   winget install usbipd
   ```
4. Copy the scripts somewhere on PATH, e.g.:
   ```powershell
   mkdir C:\Tools
   copy scripts\idf.ps1 C:\Tools
   copy scripts\Set-Esp32Port.ps1 C:\Tools
   ```
5. Add a PowerShell helper function:
   ```powershell
   notepad $PROFILE
   # Add this line:
   function idf.py { & "C:\Tools\idf.ps1" @args }
   ```
6. (Optional) One-time environment bridge:
   ```powershell
   setx WSLENV "ESPPORT/u:ESPBAUD/u:IDF_GITHUB_ASSETS/u:IDF_IMAGE/u"
   ```
7. Attach your ESP32 device to WSL:
   ```powershell
   usbipd wsl list
   usbipd wsl attach --busid <BUSID> --distribution Ubuntu
   ```
8. Use it like native:
   ```powershell
   idf.py set-target esp32
   idf.py build
   idf.py -p /dev/ttyUSB0 flash
   idf.py monitor
   idf.py fullclean
   ```

---

### Optional: Detect & Set Serial Port

Run once per session (or add `-Persist` to store it):

```powershell
Set-Esp32Port.ps1             # Interactive
Set-Esp32Port.ps1 -Auto       # Auto-pick first “Not attached”
Set-Esp32Port.ps1 -Persist    # Remember for all future shells
```

Then you can flash without specifying `-p`:
```powershell
idf.py flash
idf.py monitor
```

---

## ⚙️ Environment Variables

| Variable | Description |
|-----------|--------------|
| `IDF_IMAGE` | Override Docker image tag (default `espressif/idf:release-v5.5`). |
| `ESPPORT` | Serial device path (`/dev/ttyUSB0` or `/dev/ttyACM0`). |
| `ESPBAUD` | Default baud rate (e.g. `921600`). |
| `IDF_GITHUB_ASSETS` | Optional mirror for GitHub downloads (only used when running `idf_tools.py install` inside container). |

Example:
```bash
IDF_IMAGE=yourhubuser/esp-idf:5.5-1 ESPPORT=/dev/ttyUSB0 idf build
```

---

## 🧱 Typical Commands

| Command | Description |
|----------|-------------|
| `idf.py set-target esp32` | Choose chip target. |
| `idf.py menuconfig` | Configure project options. |
| `idf.py build` | Compile your project. |
| `idf.py -p /dev/ttyUSB0 flash` | Flash firmware to device. |
| `idf.py monitor` | Open serial monitor. |
| `idf.py fullclean` | Remove build artifacts. |
| `idf.py size` | Show build size summary. |

---

## 🔍 Troubleshooting

| Issue | Fix |
|--------|-----|
| **“docker: command not found”** | Ensure Docker is installed and accessible inside WSL or your OS PATH. |
| **“Permission denied: /dev/ttyUSB0”** | On Linux/WSL: `sudo usermod -aG dialout $USER && newgrp dialout`. |
| **macOS: flash/monitor doesn’t work** | Docker can’t access USB; use native `esptool.py`. |
| **Files owned by root** | The wrappers run `--user $(id -u):$(id -g)`; verify this wasn’t disabled. |
| **ESPPORT not found** | Run `Set-Esp32Port.ps1` or attach manually with `usbipd wsl attach …`. |
| **Slow builds on WSL2** | Move project inside WSL home (not `/mnt/c/`) for faster I/O. |

---

## 🧠 Notes on `IDF_GITHUB_ASSETS`

You do **not** need to set this for normal use — the Docker image already includes all toolchains.

Only set it if:
- You are running `idf_tools.py install` or `install.sh` manually inside the container.
- GitHub asset downloads are blocked or slow in your region.
- You want to use Espressif’s CDN mirror:
  ```bash
  export IDF_GITHUB_ASSETS="dl.espressif.com/github_assets"
  ```

Otherwise, ignore it safely.

---

## ✅ Summary

- Build & flash ESP32 apps using official Docker images — no local toolchain.
- Cross-platform: works on Linux, macOS, and Windows (via WSL2).
- Persistent & reproducible: consistent `espressif/idf` environment for your entire team.
- One-line developer experience:
  ```bash
  idf.py build && idf.py -p /dev/ttyUSB0 flash && idf.py monitor
  ```
