# esp-idf Docker



## Install

1. Put this repo in /opt
2. Set path at the end of .bashrc:
```bash
export IDF_PATH=/opt/espidf_docker/esp-idf
export PATH=$IDF_PATH/tools:$IDF_PATH/components/esptool_py/esptool:$PATH
```
3. Restart your computer

*Warning*: a version of cmake for esp-idf is in the path. If you are doing any thing cmake not related to esp32, you probably want to unset your path.

### Install Docker
#### Linux
*from https://docs.docker.com/engine/install/ubuntu/


```bash
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

2. Install the Docker packages.
```bash
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

The Docker service starts automatically after installation. To verify that Docker is running, use:
```bash
 sudo systemctl status docker
```

Some systems may have this behavior disabled and will require a manual start:
```bash
 sudo systemctl start docker
```

3. Verify that the installation is successful by running the hello-world image:
```bash
 sudo docker run hello-world
```

4. Create the docker group.
```bash
 sudo groupadd docker
```

5. Add your user to the docker group.
```bash
 sudo usermod -aG docker $USER
```

6. Log out and log back in so that your group membership is re-evaluated.

7. Verify that you can run docker commands without sudo.
```bash
 docker run hello-world
```
## Usage
### idf.py
idf.py from the command line works the same way as the normal idf.py. The first time you run it, it will pull the Espressif esp-idf docker container. This might take a while. It's about 3 gigs. After you have downloaded it the first time, you shouldn't have to download it again.

The most common idf.py commands:
- fullclean - deletes build directory
- build - builds esp32 project
- flash - flashes the esp32
- monitor - connect to the esp32 via the serial port
- menuconfig - change configuration of esp32 project
- help - help menu

## Windows (PowerShell)

This repository includes PowerShell helpers to run ESP-IDF via WSL2 + Docker Desktop and to attach USB serial devices to WSL. The short flow is:

- Prerequisites: WSL2 + Ubuntu, Docker Desktop (WSL integration), usbipd-win
- Install steps (Windows): install WSL, install Docker Desktop, install usbipd-win
- Usage: set PowerShell env vars, run `Set-Esp32Port.ps1` to attach a device, run `idf.ps1` to build/flash/monitor

- Docker Desktop with WSL integration (or Docker installed inside your WSL distro)
- usbipd-win (for attaching USB serial devices to WSL)
- Place the repo at C:\\espidf_docker

- Install via Microsoft Store (recommended):
	- Install the "App Installer" package from the Microsoft Store (this provides `winget`).

- Install manually (msixbundle from GitHub):
	1. Visit https://github.com/microsoft/winget-cli/releases
	2. Download the latest `Microsoft.DesktopAppInstaller_*.msixbundle` and install it (you may need to enable sideloading or run from an elevated PowerShell).

After installing, restart your PowerShell session and verify with `winget --version`.

Install WSL2 + Ubuntu

If you don't already have WSL2 and an Ubuntu distro installed, do the following from an elevated PowerShell prompt:

```powershell
# Install WSL and the default distro (Ubuntu) on Windows 10/11
wsl --install

# If you already have WSL but want to ensure WSL2 is the default:
wsl --set-default-version 2

# List installed distros and check status
wsl --list --verbose
```

After `wsl --install` you may need to reboot. After rebooting, you might have to do this again to install Ubuntu:
```powershell
wsl --install
```

When first launching Ubuntu, complete the distro first-run prompts (create a user account and password).

Install Docker Desktop (WSL integration)

Install Docker Desktop (recommended) and enable WSL integration:

- Using winget (run in Windows PowerShell):

Run the `winget` command in a Windows PowerShell session (preferably elevated / "Run as Administrator"). Do not run this command inside the Ubuntu WSL shell — it installs Docker Desktop on Windows, not inside WSL.

```powershell
winget install --id=Docker.DockerDesktop -e
```

- Or download Docker Desktop from https://www.docker.com/get-started and run the installer.

After installing Docker Desktop:

1. Open Docker Desktop UI -> Settings -> Resources -> WSL Integration.
2. Enable integration for your Ubuntu distro (toggle it on) and apply/restart.

Recommended startup behavior

- Enable Docker Desktop autostart: in Docker Desktop -> Settings -> General, turn on **Start Docker Desktop when you log in** so the Docker engine and `docker-desktop` integration are available automatically.
- Start your Ubuntu WSL distro manually when you need to attach USB devices (recommended): open the **Ubuntu** app or run `wsl -d Ubuntu` and keep that shell open while you run `usbipd attach` and use the device. This avoids keeping WSL running all the time while still allowing `usbipd attach` to work. 


Verify inside WSL (open an Ubuntu WSL shell):

```bash
# should print Docker server info
docker version

# test run an image
docker run --rm hello-world
```

**Troubleshooting Docker Desktop on Windows**

If you see an error like:

```
error during connect: Get "http://%2F%2F.%2Fpipe%2FdockerDesktopLinuxEngine/v1.51/version": open //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified.
```

then the Docker client cannot reach the Docker daemon. Common causes and quick fixes:

Example (actual PowerShell output seen by a user):

```
Client:
 Version:           28.5.2
 API version:       1.51
 Go version:        go1.25.3
 Git commit:        ecc6942
 Built:             Wed Nov  5 14:45:58 2025
 OS/Arch:           windows/amd64
 Context:           desktop-linux
error during connect: Get "http://%2F%2F.%2Fpipe%2FdockerDesktopLinuxEngine/v1.51/version": open //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified.
```

- **Docker Desktop is not running**: open the Docker Desktop app and wait for "Docker is running".
	- Start from PowerShell (recommended):
		```powershell
		Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
		```

- **WSL integration not enabled or distro not selected**: Docker Desktop → Settings → Resources → WSL Integration → enable your Ubuntu distro and ensure "Use the WSL 2 based engine" (General) is on.

- **Check for the named pipe / engine** (run in PowerShell):
	```powershell
	# shows if Docker Desktop process is running
	Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue

	# see docker-related named pipes (pipe will exist when the engine runs)
	Get-ChildItem \\.
	\pipe\ | Select-String -Pattern dockerDesktop
	```

- **Docker contexts**: you may be using a context that expects the Linux engine or a different daemon. Verify and switch:
	```powershell
	docker context ls
	docker context use desktop-linux   # or `default` depending on your setup
	```

- **If Docker works in WSL but not PowerShell**: open your Ubuntu WSL shell and run `docker version` and `docker run --rm hello-world` to confirm the engine is reachable from WSL. If WSL works, prefer running `idf.ps1` and tooling from WSL or ensure the desktop context is selected in PowerShell.

- **Restart Docker Desktop**: use the Docker Desktop UI to restart, or exit and reopen the app.

- **Alternative (no Docker Desktop)**: if you installed Docker inside WSL instead of using Docker Desktop, ensure the daemon (`dockerd`) is running inside the distro (systemd or a manual `dockerd` launch).

If these steps don't help, copy any error output and paste it here and I'll suggest the next action.

Notes:

- Docker Desktop requires a recent Windows 10/11 build. If you prefer not to use Docker Desktop, install Docker Engine inside your WSL distro directly following the distro's Docker install docs.
- Ensure your WSL distro is selected in Docker Desktop's WSL Integration settings so `docker` is available inside WSL shells.

### Install usbipd
- Manually (download MSI):
	1. Visit https://github.com/dorssel/usbipd-win/releases
	2. Download the latest `usbipd-win-<version>.msi` and run the installer.

Reboot Windows.

# show help
```powershell
usbipd --help
```

# list USB devices attached to Windows and their bus IDs (copy the busid you want)
```powershell
usbipd list
```

Most likely, the esp32 will show up as "USB-Enhanced-SERIAL CH343". If you are unsure which device it is, do this without the esp32 plugged in:
```powershell
usbipd list
```
then plug in the esp32 and do this again:
```powershell
usbipd list
```
The esp32 should be the new device that appears.

 # 1) Bind (share) the device so it can be attached to WSL — requires Administrator
```powershell 
usbipd bind --busid <busid>
```

# 2) In a Powershell window, run (start the WSL distro)
```powershell
wsl -d Ubuntu
```
You will see a short Ubuntu login hint such as:
```text
To run a command as administrator (user "root"), use "sudo <command>".
See "man sudo_root" for details.
```
This is not an error — it means Ubuntu started and presented its normal login hint. You do NOT need to run `wsl -d Ubuntu` from an elevated Windows PowerShell.

If you prefer to start the distro and keep it running in the background (so you don't need to keep an interactive shell open), run:

```powershell
Start-Process wsl -ArgumentList '-d Ubuntu -- bash -c "sleep infinity"'
```

That leaves the WSL distro in the `Running` state until you stop it.

# 3) Open a new Powershell window (no Admin required. Attach the device to WSL). Ensure a WSL shell is open first.
```powershell
usbipd attach --wsl --busid <busid>
```

You should see something like this:
```powershell
PS C:\espidf_docker> usbipd attach --wsl --busid 1-3
usbipd: info: Using WSL distribution 'Ubuntu' to attach; the device will be available in all WSL 2 distributions.
usbipd: info: Loading vhci_hcd module.
usbipd: info: Detected networking mode 'nat'.
usbipd: info: Using IP address 172.21.224.1 to reach the host.
```

# 4) Verify the device is attached (shows in the list)
```powershell
usbipd list
```

You should see something like this:
```powershell
PS C:\espidf_docker> usbipd list
Connected:
BUSID  VID:PID    DEVICE                                                        STATE
1-1    413c:2113  USB Input Device                                              Not shared
1-2    0000:3825  USB Input Device                                              Not shared
1-3    1a86:55d3  USB-Enhanced-SERIAL CH343 (COM3)                              Attached
2-2    0484:5750  USB Input Device                                              Not shared
2-3    8087:0029  Intel(R) Wireless Bluetooth(R)                                Not shared
4-1    057e:0000  BillBoard, USB Serial Device (COM4)                           Not shared
```
Your esp32 device should be in the "Attached" state.

# 4) When finished, detach the device
usbipd detach --busid <busid>

# list devices and attach state (used by Set-Esp32Port.ps1)
usbipd list
```

You should see something like this:
```
PS C:\espidf_docker> usbipd list    
Connected:
BUSID  VID:PID    DEVICE                                                        STATE
1-1    413c:2113  USB Input Device                                              Not shared
1-2    0000:3825  USB Input Device                                              Not shared
1-3    1a86:55d3  USB-Enhanced-SERIAL CH343 (COM3)                              Shared
2-2    0484:5750  USB Input Device                                              Not shared
2-3    8087:0029  Intel(R) Wireless Bluetooth(R)                                Not shared
4-1    057e:0000  BillBoard, USB Serial Device (COM4)                           Not shared

Persisted:
GUID                                  DEVICE
```

Common attach/detach commands:

```powershell
# attach busid 1-2 to the Ubuntu WSL distro (Admin required)
usbipd attach --wsl --busid 1-3

# detach
usbipd detach --busid 1-3
```

Notes:

- Attaching requires an elevated PowerShell session (Run as Administrator).
- After attach, allow a moment for the device to enumerate in WSL; then run `Set-Esp32Port.ps1` to detect and export the WSL device path.
- If winget or choco isn't available, use the MSI from the GitHub releases page.

Set up PowerShell environment (session)
Open PowerShell and run (session-only, effective immediately):

```powershell
$env:IDF_PATH = 'C:\\espidf_docker\\esp-idf'
$env:PATH = "$env:IDF_PATH\\tools;$env:IDF_PATH\\components\\esptool_py\\esptool;$env:PATH"
```

To persist `IDF_PATH` for your user (requires new shells to see it):

```powershell
setx IDF_PATH "C:\\espidf_docker\\esp-idf"
```

To append the tools to your user PATH (note: `setx PATH` replaces the user PATH value; be careful):

```powershell
$add = "C:\\espidf_docker\\esp-idf\\tools;C:\\espidf_docker\\esp-idf\\components\\esptool_py\\esptool"
setx PATH ("$([Environment]::GetEnvironmentVariable('PATH','User'));$add")
```

Map USB serial device into WSL (`Set-Esp32Port.ps1`)
- **Bind (host share) requires Administrator**: binding a device on the Windows host uses `usbipd bind --busid <busid>` and must be run from an elevated PowerShell session. Attaching the already-bound device into WSL (`usbipd attach --wsl ...`) normally does not require Administrator but does require a running WSL2 distro.
- Change to the tools folder and run the helper:

```powershell
cd C:\\espidf_docker\\esp-idf\\tools

# Interactive: pick device and attach to Ubuntu (default)
.\Set-Esp32Port.ps1

# Auto-attach first available not-attached device and persist ESPPORT to user env
.\Set-Esp32Port.ps1 -Distro Ubuntu -Auto -Persist

# If you already know the WSL device path (skip detect)
.\Set-Esp32Port.ps1 -Port /dev/ttyUSB0 -Persist
```

Notes:

- The helper will run the modern `usbipd` commands to attach the chosen USB device into WSL and then detects the resulting `/dev/ttyUSB*` or `/dev/ttyACM*` inside WSL. If your system is running an older `usbipd` that still exposes `wsl` subcommands, update `usbipd` or run the equivalent modern commands listed above.
- Without `-Persist` the script sets `$env:ESPPORT` for the current PowerShell session only. With `-Persist` it stores `ESPPORT` in your user environment (reopen shells to pick it up).

Run ESP-IDF commands from PowerShell (`idf.ps1`)
- `idf.ps1` wraps `idf.py` and runs everything inside your chosen WSL distro's Docker environment.

Examples (run from your ESP project folder):

```powershell
# run build
C:\\espidf_docker\\esp-idf\\tools\\idf.ps1 build

# flash using the device chosen by Set-Esp32Port.ps1
C:\\espidf_docker\\esp-idf\\tools\\idf.ps1 -p $env:ESPPORT -b 921600 flash

# open monitor
C:\\espidf_docker\\esp-idf\\tools\\idf.ps1 -p $env:ESPPORT monitor

# menuconfig
C:\\espidf_docker\\esp-idf\\tools\\idf.ps1 menuconfig
```

If you added IDF tools to your PATH (see step 1), you can run `idf.ps1` directly:

```powershell
idf.ps1 build
idf.ps1 -p $env:ESPPORT flash
```

Behavior notes

- `idf.ps1` executes inside WSL and uses Docker there. It will warn if the project directory is on a Windows-mounted filesystem (`/mnt`) because builds may be slower — consider cloning inside your WSL home for best performance.
- Ensure Docker is available inside the WSL distro used by `idf.ps1` (Docker Desktop WSL integration recommended).
- Use usbipd-win to attach USB devices to WSL so the container can access the serial port.

