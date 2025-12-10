# esp-idf Docker

Dockerized version of esp-idf for Linux, Mac and Windows.

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

#### Install Docker
*from https://docs.docker.com/engine/install/ubuntu/

1. Set up Docker's apt repository.

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

### Mac
TBA

### Windows
TBA

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

### esptool.py (Linux/macOS)
Once the repo is on your PATH (see Linux install step 2), you can run `esptool.py`
from anywhere and it will execute inside the same Docker image as `idf.py` while
passing through serial devices, `IDF_IMAGE`, etc. Example:

```bash
esptool.py --chip esp32s3 -p /dev/ttyUSB0 erase_flash
```

The wrapper simply calls `idf.py -- esptool.py …`, so any flags supported by the
real esptool are available unchanged.

### esptool.ps1 (Windows)
For PowerShell on Windows, use `esptool.ps1` located in `esp-idf/tools`. It
delegates to `idf.ps1`, which in turn launches WSL+Docker, so all arguments go to
the containerized esptool. Example from a PowerShell prompt:

```powershell
./esptool.ps1 --chip esp32c3 -p COM7 write_flash 0x0 build/app.bin
```

Make sure the script location is on your PATH or invoke it with a relative
path as shown above.



