#!/usr/bin/env python3
"""Check installer command generation; optionally exercise real locks in a container.

The live checks install only the already-installed bash package, without downloads.
They do not install Docker, remove lock files, or retry apt-get update.
"""
import argparse
import contextlib
import fcntl
import multiprocessing
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import time

TIMEOUT = "DPkg::Lock::Timeout=60"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def capture_installer(root, temporary, distro, pinned=False, repo_only=False):
    """Execute installer control flow, capturing privileged command strings only."""
    fixture = temporary / distro
    fixture.mkdir(exist_ok=True)
    (fixture / "os-release").write_text(f'ID={distro}\nVERSION_ID="24.04"\n')
    (fixture / "lsb-release").write_text('DISTRIB_CODENAME=noble\n')
    (fixture / "debian_version").write_text('12.0\n')
    source = (root / "install.sh").read_text()
    for name in ("os-release", "lsb-release", "debian_version"):
        source = source.replace(f"/etc/{name}", str(fixture / name))
    require(source.count("sh_c='sh -c'") == 1, "cannot locate command executor")
    source = source.replace("sh_c='sh -c'", "sh_c='capture_command'")
    prefix = """capture_command() {
    case "$1" in
        'apt-cache madison docker-ce') printf '%s\\n' 'docker-ce | 5:27.5.1-1~ubuntu.24.04~noble | https://example.invalid noble/stable amd64 Packages' ;;
        'apt-cache madison docker-ce-cli') printf '%s\\n' 'docker-ce-cli | 5:27.5.1-1~ubuntu.24.04~noble | https://example.invalid noble/stable amd64 Packages' ;;
        apt-cache*) printf '%s\\n' '5:27.5.1-1~ubuntu.24.04~noble' ;;
        *) printf '%s\\n' "$1" ;;
    esac
}
"""
    script = fixture / "install.sh"
    script.write_text(prefix + source)
    environment = {"PATH": str(temporary / "bin") + ":/usr/bin:/bin", "HOME": str(temporary)}
    args = ["/bin/sh", str(script), "--no-autostart"]
    if pinned:
        args += ["--version", "27.5"]
    if repo_only:
        args += ["--setup-repo"]
    result = subprocess.run(args, env=environment, text=True, capture_output=True, timeout=10)
    require(result.returncode == 0, f"installer capture failed: {result.stdout}{result.stderr}")
    return [line for line in result.stdout.splitlines() if line.startswith(("apt-get ", "DEBIAN_FRONTEND="))]


def apt_arguments(command):
    arguments = shlex.split(command)
    if arguments[0].startswith("DEBIAN_FRONTEND="):
        arguments.pop(0)
    return [argument for argument in arguments if argument != ">/dev/null"]


def command_checks(root, temporary):
    binary_directory = temporary / "bin"
    binary_directory.mkdir()
    stubs = {
        "id": "printf 'root\\n'",
        "uname": "case \"$1\" in -m) echo x86_64 ;; -r) echo test-linux ;; *) echo Linux ;; esac",
        "lsb_release": "case \"$*\" in *-u*) exit 1 ;; *codename*) printf 'Codename:\\tnoble\\n' ;; *) printf 'Release:\\t24.04\\n' ;; esac",
        "dpkg": "echo amd64",
        "sleep": ":",
    }
    for name, body in stubs.items():
        executable = binary_directory / name
        executable.write_text("#!/bin/sh\n" + body + "\n")
        executable.chmod(0o755)
    # Fail closed if an installer command escapes the capture executor.
    for name in ("apt-get", "apt-cache", "curl", "wget", "systemctl", "sudo", "su", "docker", "dnf", "yum"):
        executable = binary_directory / name
        executable.write_text("#!/bin/sh\necho 'unexpected command execution' >&2\nexit 99\n")
        executable.chmod(0o755)
    commands = None
    for distro in ("ubuntu", "debian"):
        for pinned in (False, True):
            generated = capture_installer(root, temporary, distro, pinned=pinned)
            updates = [apt_arguments(command) for command in generated if " update" in command]
            installs = [apt_arguments(command) for command in generated if " install " in command]
            require(len(updates) == 2 and len(installs) == 2, "expected two updates and two installs")
            require(all(TIMEOUT in command for command in installs), "both APT installs must wait up to 60 seconds")
            require(all(TIMEOUT not in command for command in updates), "dpkg timeout must not be applied to update")
            require(all("-y" in command and "-qq" in command for command in installs), "install flags changed")
            require(("--allow-downgrades" in installs[1]) == pinned, "version pinning flags changed")
            require("ca-certificates" in installs[0] and "curl" in installs[0], "prerequisite packages changed")
            require(any(package.startswith("docker-ce") for package in installs[1]), "Engine install missing")
            if distro == "ubuntu" and not pinned:
                commands = installs
        repository = capture_installer(root, temporary, distro, repo_only=True)
        require(sum(" install " in command for command in repository) == 1, "repo-only must install prerequisites only")
    print("PASS: Ubuntu/Debian install commands, pinned versions, and repo-only mode", flush=True)

    # Execute the rootless dependency checks with missing uidmap/iptables and an
    # available apt-get. Relocate sbin lookups to the fixture to isolate the host.
    source = (root / "rootless-install.sh").read_text()
    start = source.index("\t# uidmap dependency check")
    end = source.index("\t# ip_tables module dependency check", start)
    fragment = source[start:end]
    fragment = fragment.replace("/usr/sbin", str(temporary / "usr-sbin")).replace(":/sbin", ":" + str(temporary / "sbin"))
    result = subprocess.run(["/bin/sh", "-c", 'set -e\nINSTRUCTIONS=\nSKIP_IPTABLES=\n' + fragment + '\nprintf "%s\\n" "$INSTRUCTIONS"'],
                            env={"PATH": str(binary_directory)}, text=True, capture_output=True, timeout=10)
    require(result.returncode == 0, f"rootless checks failed: {result.stderr}")
    for package in ("uidmap", "iptables"):
        require(f"apt-get -o {TIMEOUT} -y install {package}" in result.stdout, f"missing bounded rootless {package} instruction")
    require(source.count("command -v apt-get >/dev/null 2>&1") == 2, "rootless apt-get availability checks changed")
    print("PASS: rootless APT detection and bounded uidmap/iptables instructions", flush=True)
    return commands


def hold_lock(path, ready, stop, release_after):
    with open(path, "a") as lock:
        fcntl.lockf(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        ready.send(True)
        ready.close()
        stop.wait(release_after)


@contextlib.contextmanager
def locked(path, release_after=None):
    parent, child = multiprocessing.Pipe(duplex=False)
    stop = multiprocessing.Event()
    holder = multiprocessing.Process(target=hold_lock, args=(path, child, stop, release_after))
    holder.start()
    child.close()
    try:
        require(parent.poll(5) and parent.recv(), f"could not acquire {path}")
        yield
    finally:
        stop.set()
        holder.join(5)
        if holder.is_alive():
            holder.terminate()
            holder.join(5)
        parent.close()


def run_apt(arguments, deadline=75):
    started = time.monotonic()
    result = subprocess.run(arguments, env={**os.environ, "LC_ALL": "C", "DEBIAN_FRONTEND": "noninteractive"},
                            text=True, capture_output=True, timeout=deadline)
    return result, time.monotonic() - started


def live_checks(commands):
    require(os.environ.get("DOCKER_INSTALL_LOCK_TEST_CONTAINER") == "1" and
            any(Path(marker).exists() for marker in ("/.dockerenv", "/run/.containerenv")),
            "live checks require an explicitly opted-in disposable container")
    require(os.geteuid() == 0, "live checks require root inside the container")
    print(subprocess.check_output(["apt-get", "--version"], text=True).splitlines()[0], flush=True)
    # A conflicting config default proves that the installer CLI option wins.
    configuration = Path("/etc/apt/apt.conf.d/99docker-install-lock-test")
    require(not configuration.exists(), "test APT configuration already exists")
    configuration.write_text('DPkg::Lock::Timeout "0";\n')
    try:
        # Use each generated command's options, but only an already-installed
        # package, so lock testing requires neither downloads nor Docker setup.
        installed_version = subprocess.check_output(["dpkg-query", "-W", "-f=${Version}", "bash"], text=True).strip()
        require(installed_version, "bash must already be installed")
        package = f"bash={installed_version}"
        install_commands = [command[:command.index("install") + 1] + ["--no-download", package] for command in commands]
        with locked("/var/lib/dpkg/lock-frontend"):
            control, elapsed = run_apt(["apt-get", "-y", "-qq", "install", "--no-download", package], deadline=10)
        require(control.returncode == 100 and elapsed < 5, "control must fail immediately on a real frontend lock")
        require("lock-frontend" in control.stderr, f"control failed for another reason: {control.stderr}")
        print("PASS: unmodified apt-get control fails immediately on real dpkg contention", flush=True)

        for command, path in zip(install_commands, ("/var/lib/dpkg/lock-frontend", "/var/lib/dpkg/lock")):
            with locked(path, release_after=2):
                result, elapsed = run_apt(command, deadline=90)
            require(result.returncode == 0 and elapsed >= 1.5,
                    f"install did not wait for released {path}: {elapsed:.1f}s, {result.stderr}")
            print(f"PASS: generated install waits for {path} release ({elapsed:.1f}s)", flush=True)

        with locked("/var/lib/dpkg/lock-frontend"):
            result, elapsed = run_apt(install_commands[1])
        require(result.returncode == 100 and 58 <= elapsed < 70,
                f"60-second timeout was not respected: {elapsed:.1f}s, {result.stderr}")
        require("lock-frontend" in result.stderr, f"timeout failed for another reason: {result.stderr}")
        print(f"PASS: CLI timeout overrides config=0 and fails after bounded waiting ({elapsed:.1f}s)", flush=True)

        # Negative scope check: DPkg::Lock::Timeout is not an APT lists-lock fix.
        with locked("/var/lib/apt/lists/lock"):
            result, elapsed = run_apt(["apt-get", "-o", TIMEOUT, "-qq", "update"], deadline=10)
        require(result.returncode == 100 and elapsed < 5 and "/var/lib/apt/lists/lock" in result.stderr,
                f"unexpected lists-lock behavior: {elapsed:.1f}s, {result.stderr}")
        print("PASS: update lists-lock contention remains fail-fast", flush=True)
    finally:
        configuration.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scripts-dir", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--live", action="store_true", help="exercise real dpkg locks in a disposable container (includes a 60-second timeout)")
    arguments = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="docker-install-apt-lock-") as directory:
        commands = command_checks(arguments.scripts_dir, Path(directory))
        if arguments.live:
            live_checks(commands)
    if not arguments.live:
        print("Offline checks complete. Real lock waiting requires --live in an opted-in container.")


if __name__ == "__main__":
    main()
