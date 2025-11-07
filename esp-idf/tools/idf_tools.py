#!/usr/bin/env python3
"""
Dockerized wrapper for ESP-IDF idf_tools.py (matches your idf.py UX).

Examples:
  idf_tools.py --help
  idf_tools.py install
  idf_tools.py export --format key-value
  IDF_IMAGE=espressif/idf:release-v5.5 idf_tools.py list
  idf_tools.py --pull --project ~/work/tcheck/cv1 export --format key-value
  # Run arbitrary tool inside the image:
  idf_tools.py -- cmake --version
"""

import os
import sys
import glob
import shutil
import platform
import subprocess

# Defaults & constants
DEFAULT_IMAGE = os.environ.get("IDF_IMAGE", "espressif/idf:release-v5.5")
WORKDIR_IN_CONTAINER = "/workspace"
# idf_tools.py lives in the ESP-IDF tree inside the official images here:
IDF_TOOLS_ENTRY = "/opt/esp/idf/tools/idf_tools.py"

def is_macos():
    return sys.platform == "darwin"

def is_linux():
    return sys.platform.startswith("linux")

def docker_exists():
    return shutil.which("docker") is not None

def run(cmd):
    return subprocess.call(cmd)

def find_serial_devices():
    """Kept for parity with your idf.py; not usually needed for idf_tools.py."""
    if not is_linux():
        return []
    devs = []
    for pattern in ("/dev/ttyUSB*", "/dev/ttyACM*"):
        for path in glob.glob(pattern):
            devs += ["--device", f"{path}:{path}"]
    return devs

def parse_args(argv):
    """
    Wrapper flags (consumed here):
      --image <tag>         override docker image (default from $IDF_IMAGE)
      --pull                docker pull before run
      --no-devices          don’t map /dev/ttyUSB* / /dev/ttyACM*
      --no-user-map         don’t map uid:gid (file ownership)
      --ccache              mount host ccache into container
      --project <path>      mount this dir as /workspace (default: $PWD)
      --                    everything after goes as raw command (skip idf_tools)
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
        ccache_host = os.path.join(os.path.expanduser("~"), ".ccache")
        os.makedirs(ccache_host, exist_ok=True)
        mounts += ["-v", f"{ccache_host}:/home/esp/.ccache"]
    return mounts

def main():
    if not docker_exists():
        sys.stderr.write("Error: Docker is not installed or not in PATH.\n")
        sys.exit(1)

    image, pull, pass_devices, user_map, use_ccache, project_dir, raw_cmd, tool_args = parse_args(sys.argv[1:])
    if project_dir is None:
        project_dir = os.getcwd()

    if pull:
        rc = run(["docker", "pull", image])
        if rc != 0:
            sys.exit(rc)

    docker_cmd = ["docker", "run", "--rm", "-it"]

    # Map uid:gid so files created are owned by the host user
    if user_map and (is_linux() or is_macos()):
        try:
            docker_cmd += ["--user", f"{os.getuid()}:{os.getgid()}"]
        except Exception:
            pass

    # Pass through useful env vars (extend if you like)
    for key in ("IDF_GITHUB_ASSETS", "ESPPORT", "ESPBAUD", "IDF_IMAGE"):
        val = os.environ.get(key)
        if val:
            docker_cmd += ["-e", f"{key}={val}"]

    # Mount project & optional caches
    docker_cmd += build_mounts(project_dir, use_ccache)
    docker_cmd += ["-w", WORKDIR_IN_CONTAINER]

    # Serial devices (mostly irrelevant for idf_tools.py, but harmless)
    if pass_devices and is_linux():
        docker_cmd += find_serial_devices()
        # Best-effort supplementary groups for device access
        try:
            gids = set()
            for pattern in ("/dev/ttyUSB*", "/dev/ttyACM*"):
                for path in glob.glob(pattern):
                    try:
                        gids.add(os.stat(path).st_gid)
                    except Exception:
                        pass
            for gid in sorted(gids):
                docker_cmd += ["--group-add", str(gid)]
        except Exception:
            pass

    docker_cmd += [image]
    inner = raw_cmd if raw_cmd else [IDF_TOOLS_ENTRY] + tool_args

    # Debug:
    # import shlex; print(" ".join(shlex.quote(x) for x in docker_cmd + inner))

    sys.exit(run(docker_cmd + inner))

if __name__ == "__main__":
    main()
