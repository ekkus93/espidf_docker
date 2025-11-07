#!/usr/bin/env python3
import os, sys, shlex, subprocess, glob, pathlib

CONTAINER = os.environ.get("ESP_IDF_DOCKER_CONTAINER", "esp-idf")
IMAGE     = os.environ.get("ESP_IDF_DOCKER_IMAGE", "espressif/idf:release-v5.5")
WORKDIR   = os.getcwd()
IDF_PATH  = "/opt/esp/idf"
PY        = "/opt/esp/python_env/idf5.5_py3.12_env/bin/python3"
MONITOR   = f"{IDF_PATH}/tools/idf_monitor.py"

def sh(cmd):
    return subprocess.check_output(cmd, text=True).strip()

def container_exists(name):
    try:
        return name in sh(["docker","ps","-a","--format","{{.Names}}"]).splitlines()
    except Exception:
        return False

def container_running(name):
    try:
        return name in sh(["docker","ps","--format","{{.Names}}"]).splitlines()
    except Exception:
        return False

def parse_port(argv):
    # explicit --port / -p
    for i,a in enumerate(argv):
        if a in ("--port","-p") and i+1 < len(argv):
            return argv[i+1]
        if a.startswith("--port="):
            return a.split("=",1)[1]
        if a.startswith("-p") and len(a)>2:   # e.g. -p/dev/ttyUSB0
            return a[2:]
    # env hints
    for k in ("IDF_PORT","ESPPORT","ESPTOOL_PORT"):
        v = os.environ.get(k)
        if v: return v
    # simple auto-detect
    for pat in ("/dev/ttyUSB*","/dev/ttyACM*","/dev/cu.SLAB_USBtoUART","/dev/cu.usbserial*"):
        m = sorted(glob.glob(pat))
        if m: return m[0]
    return None

def map_host_paths_to_container(argv):
    """If an arg is an existing path under CWD, rewrite to /host/… so it resolves inside container."""
    mapped = []
    wd = pathlib.Path(WORKDIR).resolve()
    for a in argv:
        try:
            p = pathlib.Path(a)
            if p.is_absolute():
                rp = p.resolve()
                try:
                    rp.relative_to(wd)
                    rel = rp.relative_to(wd)
                    mapped.append("/host/" + str(rel).replace("\\","/"))
                    continue
                except ValueError:
                    # absolute but outside CWD; leave as-is (won't exist in container)
                    pass
            else:
                if (wd / p).exists():
                    mapped.append("/host/" + str(p).replace("\\","/"))
                    continue
        except Exception:
            pass
        mapped.append(a)
    return mapped

def main():
    args = map_host_paths_to_container(sys.argv[1:])
    port = parse_port(args)

    inner = f'export IDF_PATH={shlex.quote(IDF_PATH)}; ' \
            f'export PYTHONUNBUFFERED=1; ' \
            f'{shlex.quote(PY)} {shlex.quote(MONITOR)} ' + " ".join(map(shlex.quote, args))

    def exec_in_container():
        cmd = ["docker","exec","-it",CONTAINER,"bash","-lc",inner]
        # preserve terminal size & TERM for nicer monitor UX
        for envk in ("TERM","COLUMNS","LINES"):
            if envk in os.environ:
                cmd[2:2] = ["-e", f"{envk}={os.environ[envk]}"]
        sys.exit(subprocess.call(cmd))

    if container_running(CONTAINER):
        exec_in_container()

    if container_exists(CONTAINER):
        subprocess.check_call(["docker","start",CONTAINER])
        exec_in_container()

    # One-shot run
    run = ["docker","run","--rm","-it"]
    if port:
        run += ["--device", port]
    if os.environ.get("ESP_DOCKER_PRIVILEGED","0") == "1":
        run += ["--privileged"]
    # Propagate terminal env for proper curses behavior
    for envk in ("TERM","COLUMNS","LINES"):
        if envk in os.environ:
            run += ["-e", f"{envk}={os.environ[envk]}"]
    run += [
        "-v", f"{WORKDIR}:/host",
        "-w", "/host",
        IMAGE, "bash","-lc", inner
    ]
    sys.exit(subprocess.call(run))

if __name__ == "__main__":
    main()
