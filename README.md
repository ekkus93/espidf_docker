# esp-idf Docker



## Install
### Linux
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

### Windows (PowerShell)

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

Download Docker Desktop from https://www.docker.com/get-started and run the installer.

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

### Install usbipd

- Install usbipd on Windows (MSI):
  1. Visit https://github.com/dorssel/usbipd-win/releases
  2. Download the latest `usbipd-win-<version>.msi` and run the installer.

Reboot Windows after installing.

The `Set-Esp32Port.ps1` helper is the simplest and recommended approach — it handles detection, prompts, and sets `ESPPORT` for you.

Run as Adminstrator in Powershell:
```powershell
cd C:/espidf_docker/esp-idf/tools
powershell -NoProfile -ExecutionPolicy Bypass -File .\Set-Esp32Port.ps1 -Distro Ubuntu
```

You should see something like this if it was successful:
```powershell
PS C:\espidf_docker\esp-idf\tools> powershell -NoProfile -ExecutionPolicy Bypass -File .\Set-Esp32Port.ps1 -Distro Ubuntu
>> usbipd list
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

Enter BUSID to attach (e.g., 1-2): 1-3
Preparing BUSID 1-3 for attach to 'Ubuntu'...
Attaching BUSID 1-3 to WSL distro 'Ubuntu'...
Detected serial device: /dev/ttyACM0
USB serial device mapped to /dev/ttyACM0 (ESPPORT)
Example: idf.ps1 -p /dev/ttyACM0 flash
Example: idf.ps1 -p /dev/ttyACM0 monitor
```

If you are unsure which device you should use, do the following:
```powershell
cd C:/espidf_docker/esp-idf/tools
powershell -NoProfile -ExecutionPolicy Bypass -File .\Find-Esp32Usb.ps1
```
You should see something like this:
PS C:\espidf_docker\esp-idf\tools> powershell -NoProfile -ExecutionPolicy Bypass -File .\Find-Esp32Usb.ps1
Unplug the ESP32 USB cable, then press Enter to continue.

Captured 5 currently connected device(s).
Now plug in the ESP32, wait for it to enumerate, then press Enter.

Captured 6 device(s) after reconnect.
New USB device(s) detected:
  BusId: 1-3
  VID:PID: 303a:1001
  Description: USB Serial Device (COM5), USB JTAG/serial debug unit
  State: Not shared

You can now use the detected BusId with Set-Esp32Port.ps1 or usbipd attach.

#### idf
Run ESP-IDF commands from PowerShell (`idf.ps1`)
- `idf.ps1` wraps `idf.py` and runs everything inside your chosen WSL distro's Docker environment.

Update security in Powershell to run scripts:
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

Examples (run from your ESP project folder):

```powershell
# In the top level of your esp32 project, run build
```powershell
idf.ps1 build
```

# flash using the device chosen by Set-Esp32Port.ps1
idf.ps1 -p $env:ESPPORT -b 921600 flash

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

