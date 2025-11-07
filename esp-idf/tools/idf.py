#!/usr/bin/env python3
"""
Dockerized ESP-IDF wrapper for Linux & macOS.

Usage (exactly like native idf.py):
  idf set-target esp32
  idf menuconfig
  idf build
  idf -p /dev/ttyUSB0 -b 921600 flash
  idf monitor
  idf fullclean

Extras:
  IDF_IMAGE=yourhubuser/esp-idf:5.5-1 idf build
  idf --image yourhubuser/esp-idf:5.5-1 --pull build
  idf --ccache build
  idf --project ~/src/myproj build
  idf -- cmake --version    # run arbitrary tool in the image
"""

import os
import sys
import glob
import shutil
import platform
import subprocess

DEFAULT_IMAGE = os.environ.get("IDF_IMAGE", "espressif/idf:release-v5.5")
WORKDIR_IN_CONTAINER = "/workspace"
IDF_ENTRY = "idf.py"

def is_macos():
    return sys.platform == "darwin"

def is_linux():
    return sys.platform.startswith("linux")

def docker_exists():
    return shutil.which("docker") is not None

def run(cmd):
    return subprocess.call(cmd)

def find_serial_devices():
    """Only meaningful on Linux; macOS Docker can’t pass USB serial."""
    if not is_linux():
        return []
    devs = []
    for pattern in ("/dev/ttyUSB*", "/dev/ttyACM*"):
        for path in glob.glob(pattern):
            devs += ["--device", f"{path}:{path}"]
    return devs

def parse_args(argv):
    """
    Supported wrapper flags (consumed here, not passed to idf.py):
      --image <tag>         override docker image
      --pull                docker pull before run
      --no-devices          don’t map /dev/ttyUSB* / /dev/ttyACM*
      --no-user-map         don’t map uid:gid
      --ccache              mount host ccache into the container
      --project <path>      mount specific directory (default: $PWD)
      --                    everything after goes as raw command (skip idf.py)
    """
    image = DEFAULT_IMAGE
    pull = False
    pass_devices = True
    user_map = True
    use_ccache = False
    project_dir = None

    raw_cmd = None
    if "--" in argv:
        idx = argv.index("--")
        wrapper_args = argv[:idx]
        raw_cmd = argv[idx+1:]
    else:
        wrapper_args = argv

    i = 0
    consumed = set()
    while i < len(wrapper_args):
        a = wrapper_args[i]
        if a == "--image" and i + 1 < len(wrapper_args):
            image = wrapper_args[i+1]; consumed |= {i, i+1}; i += 2; continue
        if a == "--pull":
            pull = True; consumed.add(i); i += 1; continue
        if a == "--no-devices":
            pass_devices = False; consumed.add(i); i += 1; continue
        if a == "--no-user-map":
            user_map = False; consumed.add(i); i += 1; continue
        if a == "--ccache":
            use_ccache = True; consumed.add(i); i += 1; continue
        if a == "--project" and i + 1 < len(wrapper_args):
            project_dir = os.path.abspath(os.path.expanduser(wrapper_args[i+1]))
            consumed |= {i, i+1}; i += 2; continue
        i += 1

    rest = [arg for idx, arg in enumerate(wrapper_args) if idx not in consumed]
    return image, pull, pass_devices, user_map, use_ccache, project_dir, raw_cmd, rest

def build_mounts(project_dir, use_ccache):
    mounts = []
    mounts += ["-v", f"{project_dir}:{WORKDIR_IN_CONTAINER}"]
    if use_ccache:
        # Host ccache directory; adjust container home if your base image uses another user
        ccache_host = os.path.join(os.path.expanduser("~"), ".ccache")
        os.makedirs(ccache_host, exist_ok=True)
        # Common home paths in Espressif images: /home/esp or /home/esp32 or similar.
        # We don’t need to know the exact user; ccache path is configurable via env as needed.
        mounts += ["-v", f"{ccache_host}:/home/esp/.ccache"]
    return mounts

def warn_if_flash_on_macos(idf_args, raw_cmd):
    if not is_macos():
        return
    # If running idf.py, check for flash/monitor; if raw command, check general hint
    tokens = (idf_args if raw_cmd is None else raw_cmd)
    joined = " ".join(tokens)
    if any(k in joined.split() for k in ("flash", "app-flash", "erase-flash", "monitor", "dfu", "dfu-flash")):
        sys.stderr.write(
            "Note: Docker on macOS cannot pass USB serial devices to Linux containers.\n"
            "      You can still build in Docker, but for flashing/monitor either:\n"
            "        - use native esptool.py on macOS, or\n"
            "        - use a Linux/WSL machine for flashing.\n"
        )

def main():
    if not docker_exists():
        sys.stderr.write("Error: Docker is not installed or not in PATH.\n")
        sys.exit(1)

    image, pull, pass_devices, user_map, use_ccache, project_dir, raw_cmd, idf_args = parse_args(sys.argv[1:])
    if project_dir is None:
        project_dir = os.getcwd()

    if pull:
        rc = run(["docker", "pull", image])
        if rc != 0:
            sys.exit(rc)

    docker_cmd = ["docker", "run", "--rm", "-it"]

    # Map uid:gid so files created in repo are owned by you (Linux/macOS)
    if user_map and (is_linux() or is_macos()):
        try:
            docker_cmd += ["--user", f"{os.getuid()}:{os.getgid()}"]
        except Exception:
            pass

    # Env passthrough (useful but optional)
    for key in ("IDF_GITHUB_ASSETS", "ESPPORT", "ESPBAUD", "IDF_IMAGE"):
        val = os.environ.get(key)
        if val:
            docker_cmd += ["-e", f"{key}={val}"]

    # Mount project (and optional caches)
    docker_cmd += build_mounts(project_dir, use_ccache)
    docker_cmd += ["-w", WORKDIR_IN_CONTAINER]

    # Serial devices (Linux only)
    if pass_devices and is_linux():
        docker_cmd += find_serial_devices()

        # Add host device groups (for example `dialout`) as supplementary groups
        # inside the container. This helps when the container process runs with
        # the same numeric UID:GID as the host user but doesn't have the
        # supplementary groups (so it cannot open /dev/ttyUSB* nodes).
        try:
            gids = set()
            for pattern in ("/dev/ttyUSB*", "/dev/ttyACM*"):
                for path in glob.glob(pattern):
                    try:
                        gids.add(os.stat(path).st_gid)
                    except Exception:
                        # ignore files that vanish or stat failures
                        pass
            for gid in sorted(gids):
                docker_cmd += ["--group-add", str(gid)]
        except Exception:
            # best-effort only; if something fails, continue without group-add
            pass

    # Compose final command
    docker_cmd += [image]
    inner = raw_cmd if raw_cmd else [IDF_ENTRY] + idf_args
    warn_if_flash_on_macos(idf_args, raw_cmd)

    # Debug: print the command if needed
    # print(" ".join(shlex.quote(x) for x in docker_cmd + inner))

    sys.exit(run(docker_cmd + inner))

if __name__ == "__main__":
    main()
