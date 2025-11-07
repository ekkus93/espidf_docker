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

## Usage
### idf.py
idf.py from the command line works the same way as the normal idf.py. The first time you run it, it will pull the Espressif esp-idf docker container. This might take a while. It's about 3 gigs. After you have downloaded it the first time, you shouldn't have to download it again.

The most common idf.py commands:
fullclean - deletes build directory
build - builds esp32 project
flash - flashes the esp32
monitor - connect to the esp32 via the serial port
menuconfig - change configuration of esp32 project
help - help menu

