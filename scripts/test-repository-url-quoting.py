#!/usr/bin/env python3
"""Offline checks that execute RPM repository commands against inert mocks."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = Path(os.environ.get("INSTALLER_UNDER_TEST", ROOT / "install.sh"))
TEST_SHELL = shutil.which(os.environ.get("TEST_SHELL", "sh"))
if TEST_SHELL is None:
    raise SystemExit("ERROR: TEST_SHELL was not found")

# Keep the installer unchanged except for deferring its final entry point.
source = INSTALLER.read_text()
if not source.endswith("\ndo_install\n"):
    raise SystemExit("ERROR: expected the installer's final do_install entry point")

mock_source = """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

command = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["MOCK_ARGUMENT_LOG"], "a") as log:
    log.write(json.dumps({"command": command, "args": args}) + "\\n")
if command == "rm":
    expected = ["-f", "/etc/yum.repos.d/docker-ce.repo", "/etc/yum.repos.d/docker-ce-staging.repo"]
    if args != expected:
        raise SystemExit("ERROR: unexpected removal command in offline test")
elif command not in ("dnf5", "dnf", "yum", "yum-config-manager"):
    raise SystemExit("ERROR: forbidden command executed in offline test: " + command)
"""

wrapper_source = """#!/bin/sh
set -e
. "$TEST_INSTALLER"
# Control host detection only; repository command generation and sh -c execution
# still come from the actual installer.
id() { printf '%s\\n' root; }
get_distribution() { printf '%s\\n' "$TEST_DISTRO"; }
is_wsl() { false; }
check_forked() { :; }
command_exists() {
    case "$1" in
        dnf5) [ "$TEST_MANAGER" = dnf5 ] ;;
        dnf) [ "$TEST_MANAGER" != yum ] ;;
        docker|lsb_release) return 1 ;;
        *) command -v "$@" >/dev/null 2>&1 ;;
    esac
}
dist_version=44
do_install
"""

with tempfile.TemporaryDirectory(prefix="docker-install-repository-url-") as temp:
    directory = Path(temp)
    mock_bin = directory / "bin"
    mock_bin.mkdir()
    production = directory / "install-functions.sh"
    production.write_text(source[:-len("do_install\n")])
    wrapper = directory / "run-installer.sh"
    wrapper.write_text(wrapper_source)
    mock = directory / "mock-command"
    mock.write_text(mock_source)
    mock.chmod(0o755)
    for command in ("dnf5", "dnf", "yum", "yum-config-manager", "rm",
                    "curl", "wget", "sudo", "su", "docker", "systemctl"):
        (mock_bin / command).symlink_to(mock)
    # Exercise the chosen shell for both the installer and its inner sh -c.
    (mock_bin / "sh").symlink_to(TEST_SHELL)
    log = directory / "arguments.jsonl"
    substitution_marker = directory / "substitution-executed"
    backtick_marker = directory / "backtick-executed"
    default_url = "https://download.docker.com"
    special = 'space & single\' double" $HOME $(touch "$TEST_SUBSTITUTION_MARKER") ' + chr(96) + 'touch "$TEST_BACKTICK_MARKER"' + chr(96)
    cases = [
        ("default", {}, [], default_url, "docker-ce.repo"),
        ("custom URL", {"DOWNLOAD_URL": "https://mirror.invalid/" + special},
         [], "https://mirror.invalid/" + special, "docker-ce.repo"),
        ("custom repo file", {"REPO_FILE": special + ".repo"},
         [], default_url, special + ".repo"),
        ("URL and repo file", {"DOWNLOAD_URL": "https://mirror.invalid/" + special,
                              "REPO_FILE": special + ".repo"},
         [], "https://mirror.invalid/" + special, special + ".repo"),
        ("newline characters", {"DOWNLOAD_URL": "https://mirror.invalid/a\nb\t",
                                "REPO_FILE": "line\nfile.repo\n"},
         [], "https://mirror.invalid/a\nb\t", "line\nfile.repo\n"),
        ("staging default", {"DOWNLOAD_URL": "https://download-stage.docker.com"},
         [], "https://download-stage.docker.com", "docker-ce-staging.repo"),
        ("staging explicit repo", {"DOWNLOAD_URL": "https://download-stage.docker.com",
                                  "REPO_FILE": special + ".repo"},
         [], "https://download-stage.docker.com", special + ".repo"),
        ("mirror overrides custom URL", {"DOWNLOAD_URL": "https://mirror.invalid/" + special,
                                        "REPO_FILE": special + ".repo"},
         ["--mirror", "Aliyun"], "https://mirrors.aliyun.com/docker-ce",
         special + ".repo"),
    ]
    checks = 0
    for manager in ("dnf5", "dnf", "yum"):
        distro = "centos" if manager == "yum" else "fedora"
        for channel in ("stable", "test"):
            for label, overrides, arguments, base_url, repo_file in cases:
                log.write_text("")
                substitution_marker.unlink(missing_ok=True)
                backtick_marker.unlink(missing_ok=True)
                # Discard inherited VERSION, mirror, dry-run and installer settings.
                environment = {
                    "PATH": str(mock_bin) + os.pathsep + os.environ["PATH"],
                    "HOME": str(directory),
                    "TEST_INSTALLER": str(production),
                    "TEST_MANAGER": manager,
                    "TEST_DISTRO": distro,
                    "MOCK_ARGUMENT_LOG": str(log),
                    "TEST_SUBSTITUTION_MARKER": str(substitution_marker),
                    "TEST_BACKTICK_MARKER": str(backtick_marker),
                    **overrides,
                }
                result = subprocess.run(
                    [TEST_SHELL, str(wrapper), "--setup-repo", "--channel", channel, *arguments],
                    env=environment, text=True, capture_output=True, timeout=10)
                name = f"{manager}/{channel}/{label}"
                if result.returncode:
                    raise SystemExit(f"FAIL (offline): {name}\n{result.stdout}{result.stderr}")
                calls = [json.loads(line) for line in log.read_text().splitlines()]
                expected_url = f"{base_url}/linux/{distro}/{repo_file}"
                if manager == "dnf5":
                    expected = {"command": "dnf5", "args": ["config-manager", "addrepo",
                                "--overwrite", "--save-filename=docker-ce.repo",
                                "--from-repofile=" + expected_url]}
                    repository_calls = [call for call in calls if call["command"] == "dnf5"
                                        and "addrepo" in call["args"]]
                else:
                    expected = {"command": "dnf" if manager == "dnf" else "yum-config-manager",
                                "args": (["config-manager"] if manager == "dnf" else []) +
                                ["--add-repo", expected_url]}
                    repository_calls = [call for call in calls if "--add-repo" in call["args"]]
                if repository_calls != [expected]:
                    raise SystemExit(f"FAIL (offline): {name}: URL arguments changed\n"
                                     f"expected={expected!r}\nactual={repository_calls!r}")
                if substitution_marker.exists() or backtick_marker.exists():
                    raise SystemExit(f"FAIL (offline): {name}: command substitution executed")
                if any("docker-ce" in call["args"] and "install" in call["args"] for call in calls):
                    raise SystemExit(f"FAIL (offline): {name}: setup-repo installed Docker")
                checks += 1
        print(f"PASS (offline): {manager}: exact URL argument and no command substitution")
    print(f"PASS (offline): {checks} RPM repository cases with {TEST_SHELL}")
    print("No network requests, package installation, or host repository changes were performed.")
