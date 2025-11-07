#!/usr/bin/env python3
import os, sys, shlex, subprocess, glob

CONTAINER = os.environ.get("ESP_IDF_DOCKER_CONTAINER", "esp-idf")
IMAGE     = os.environ.get("ESP_IDF_DOCKER_IMAGE", "espressif/idf:release-v5.5")
WORKDIR   = os.getcwd()

def sh(cmd):
    return subprocess.check_output(cmd, text=True).strip()

def container_exists(name):
    try:
        out = sh(["docker","ps","-a","--format","{{.Names}}"])
        return any(line.strip()==name for line in out.splitlines())
    except Exception:
        return False

def container_running(name):
    try:
        out = sh(["docker","ps","--format","{{.Names}}"])
        return any(line.strip()==name for line in out.splitlines())
    except Exception:
        return False

def parse_port(argv):
    # explicit --port/-p
    for i,a in enumerate(argv):
        if a in ("--port","-p") and i+1 < len(argv):
            return argv[i+1]
        if a.startswith("--port="):
            return a.split("=",1)[1]
        if a.startswith("-p") and len(a)>2:
            return a[2:]
    # env hints
    for envk in ("IDF_PORT","ESPPORT","ESPTOOL_PORT"):
        v=os.environ.get(envk)
        if v: return v
    # auto-detect common USB/ACM devices
    for pat in ("/dev/ttyUSB*","/dev/ttyACM*","/dev/cu.SLAB_USBtoUART","/dev/cu.usbserial*"):
        matches=sorted(glob.glob(pat))
        if matches: return matches[0]
    return None

def main():
    args = sys.argv[1:]
    port = parse_port(args)

    # prefer the IDF-managed python env esptool
    inner = "/opt/esp/python_env/idf5.5_py3.12_env/bin/python3 -m esptool " + " ".join(map(shlex.quote, args))

    # If a dev container is running, exec into it
    if container_running(CONTAINER):
        cmd = ["docker","exec","-i",CONTAINER,"bash","-lc",inner]
        sys.exit(subprocess.call(cmd))

    # If it exists but stopped, start then exec
    if container_exists(CONTAINER):
        subprocess.check_call(["docker","start",CONTAINER])
        cmd = ["docker","exec","-i",CONTAINER,"bash","-lc",inner]
        sys.exit(subprocess.call(cmd))

    # One-shot run (no persistent container)
    run = ["docker","run","--rm","-i"]
    # attach a TTY if we have one (good for monitor, optional here)
    if sys.stdin.isatty():
        run.append("-t")
    # pass through serial device if we found one
    if port:
        run += ["--device", port]
    # optional: allow stricter hosts to access serial
    if os.environ.get("ESP_DOCKER_PRIVILEGED","0") == "1":
        run += ["--privileged"]
    # mount current project as /host and run from there
    run += ["-v", f"{WORKDIR}:/host", "-w", "/host", IMAGE, "bash","-lc", inner]
    sys.exit(subprocess.call(run))

if __name__ == "__main__":
    main()
