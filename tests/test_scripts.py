import json
import os
import pwd
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"

MOCK = r"""
#!/usr/bin/env python3
import json
import os
from pathlib import Path
import signal
import sys
import time

name = Path(sys.argv[0]).name
args = sys.argv[1:]
root = Path(os.environ["FIXTURE"])
session = os.environ["TEST_SESSION"]

with (root / f"{name}.log").open("a") as log:
    log.write(json.dumps([session, *args]) + "\n")

if name == "id":
    print(f"pokeidle-{session}")
elif name == "xauth":
    sys.stdin.read()
elif name == "ss":
    port = args[-1].rsplit(":", 1)[-1]
    if (root / f"down-{port}").exists():
        sys.exit(0)
    print(f"LISTEN 0 128 127.0.0.1:{port} 0.0.0.0:*")
    if (root / f"exposed-{port}").exists():
        print(f"LISTEN 0 128 0.0.0.0:{port} 0.0.0.0:*")
elif name == "tailscale":
    if args == ["ip", "-4"]:
        print("100.64.0.10")
    elif args[-1] == "--json":
        config = root / "serve.json"
        print(config.read_text() if config.exists() else "null")
elif name == "systemctl":
    if args[0] == "restart" and (root / f"fail-{args[-1]}").exists():
        sys.exit(1)
elif name in {"Xtigervnc", "startxfce4", "chromium"}:
    if name == "chromium" and (root / f"crash-{session}").exists():
        sys.exit(17)
    def terminate(signum, frame):
        sys.exit(0 if signum == signal.SIGTERM else 17)
    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGUSR1, terminate)
    (root / f"{name}-{session}.pid").write_text(str(os.getpid()))
    while True:
        time.sleep(0.02)
        if name == "chromium" and (root / f"close-{session}").exists():
            sys.exit(0)
"""


class ScriptTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="pokeidle-test-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        self.bin_dir = bin_dir
        mock = bin_dir / "mock"
        mock.write_text(MOCK.lstrip())
        mock.chmod(0o755)
        for command in (
            "id", "xauth", "Xtigervnc", "xdpyinfo", "dbus-update-activation-environment",
            "xset", "xfconf-query", "startxfce4", "chromium", "ss", "tailscale", "systemctl",
        ):
            (bin_dir / command).symlink_to(mock)

        common = (SCRIPTS / "common.sh").read_text()
        # Os comandos administrativos usam mocks e executam como usuário local.
        (self.root / "common.sh").write_text(common + "\nrequire_root() { :; }\n")
        health = (SCRIPTS / "chromium-health.sh").read_text()
        (self.root / "chromium-health.sh").write_text(health)
        for script in ("access", "doctor", "recover"):
            content = (SCRIPTS / f"{script}.sh").read_text()
            content = content.replace(
                "/usr/local/lib/pokeidle-cloud/common.sh", f'"{self.root}/common.sh"'
            )
            content = content.replace(
                "/usr/local/lib/pokeidle-cloud/chromium-health.sh",
                f'"{self.root}/chromium-health.sh"',
            )
            (self.root / f"{script}.sh").write_text(content)

        content = (SCRIPTS / "session.sh").read_text()
        for original, fixture in (
            ('[[ $EUID != 0 && $(id -un)', '[[ $(id -un)'),
            ('export HOME="$session_home"', 'export HOME="$FIXTURE/home-$session_id"'),
            ('"/run/user/$EUID"', '"$FIXTURE/runtime-$session_id"'),
            ('[[ -S $XDG_RUNTIME_DIR/bus ]]', '[[ -f $XDG_RUNTIME_DIR/bus ]]'),
            ("/snap/bin/chromium", "chromium"),
            ("sleep 5 &", "sleep 0.05 &"),
            ("sleep 15 &", "sleep 0.05 &"),
        ):
            self.assertIn(original, content)
            content = content.replace(original, fixture)
        (self.root / "session.sh").write_text(content)

    def env(self, session="1"):
        return dict(os.environ, FIXTURE=str(self.root), TEST_SESSION=session,
                    PATH=f"{self.root / 'bin'}:{os.environ['PATH']}")

    def run_script(self, name, *args):
        return subprocess.run(
            ["bash", str(self.root / f"{name}.sh"), *args],
            env=self.env(), text=True, capture_output=True, timeout=6,
        )

    def log(self, command):
        path = self.root / f"{command}.log"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def run_health(self, pid_file, profile):
        user = pwd.getpwuid(os.getuid()).pw_name
        return subprocess.run(
            [
                "bash",
                str(self.root / "chromium-health.sh"),
                user,
                str(pid_file),
                str(profile),
            ],
            env=self.env(), text=True, capture_output=True, timeout=6,
        )

    def wait_for(self, predicate):
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.025)
        self.fail("tempo esgotado aguardando processo simulado")

    def start_session(self, session, password=True):
        home = self.root / f"home-{session}"
        home.mkdir()
        (home / ".vnc").mkdir()
        if password:
            password_file = home / ".vnc/passwd"
            password_file.write_bytes(bytes(8))
            password_file.chmod(0o600)
        runtime = self.root / f"runtime-{session}"
        runtime.mkdir()
        (runtime / "bus").touch()
        log = (self.root / f"session-{session}.log").open("w+")
        self.addCleanup(log.close)
        process = subprocess.Popen(
            ["bash", str(self.root / "session.sh"), session],
            env=self.env(session), text=True, stdout=log, stderr=log, start_new_session=True,
        )
        self.addCleanup(self.stop_process, process)
        return process

    @staticmethod
    def stop_process(process):
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=4)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=3)

    def test_two_desktops_and_browser_recovery(self):
        first, second = (self.start_session(session) for session in ("1", "2"))
        self.wait_for(lambda: all((self.root / f"chromium-{i}.pid").exists() for i in (1, 2)))
        servers = {entry[0]: entry[1:] for entry in self.log("Xtigervnc")}
        for session, port, display in (("1", "5901", ":71"), ("2", "5902", ":72")):
            args = servers[session]
            self.assertEqual(args[0], display)
            self.assertEqual(args[args.index("-rfbport") + 1], port)
            self.assertIn("-localhost", args)
            self.assertIn("VncAuth", args)
        browsers = {entry[0]: entry[1:] for entry in self.log("chromium")}
        self.assertIn(
            f"--user-data-dir={self.root}/home-1/snap/chromium/common/pokeidle-profile",
            browsers["1"],
        )
        self.assertIn(
            f"--user-data-dir={self.root}/home-2/snap/chromium/common/pokeidle-profile",
            browsers["2"],
        )
        second_pid_file = self.root / "chromium-2.pid"
        second_pid = int(second_pid_file.read_text())
        first_pid_file = self.root / "chromium-1.pid"
        first_pid = int(first_pid_file.read_text())
        os.kill(first_pid, signal.SIGUSR1)
        self.wait_for(lambda: first_pid_file.read_text() not in ("", str(first_pid)))
        self.assertEqual(second_pid_file.read_text(), str(second_pid))

        self.stop_process(first)
        self.assertEqual(first.returncode, 0)
        self.assertIsNone(second.poll())
        os.kill(second_pid, 0)
        self.assertFalse((self.root / "runtime-1/pokeidle-cloud/chromium.pid").exists())

    def test_clean_browser_exit_keeps_desktop(self):
        process = self.start_session("1")
        self.wait_for(lambda: (self.root / "chromium-1.pid").exists())
        (self.root / "close-1").touch()
        self.wait_for(lambda: not (self.root / "runtime-1/pokeidle-cloud/chromium.pid").exists())
        self.assertIsNone(process.poll())
        self.assertEqual(len(self.log("chromium")), 1)
        os.kill(int((self.root / "Xtigervnc-1.pid").read_text()), signal.SIGTERM)
        self.assertEqual(process.wait(timeout=6), 1)

    def test_browser_retries_are_bounded(self):
        (self.root / "crash-2").touch()
        process = self.start_session("2")
        log = self.root / "session-2.log"
        self.wait_for(lambda: "Chromium encerrou repetidamente" in log.read_text())
        self.assertEqual(len(self.log("chromium")), 3)
        self.assertIsNone(process.poll())

    def test_missing_password_stops_before_vnc(self):
        process = self.start_session("1", password=False)
        self.assertEqual(process.wait(timeout=6), 1)
        self.assertFalse(self.log("Xtigervnc"))

    def test_access_refuses_any_public_listener_before_configuring_serve(self):
        public = self.root / "exposed-5902"
        public.touch()
        result = self.run_script("access", "enable")
        self.assertEqual(result.returncode, 1)
        self.assertIn("5902", result.stderr)
        self.assertFalse(any(entry[1] == "serve" for entry in self.log("tailscale")))
        public.unlink()
        result = self.run_script("access", "enable")
        self.assertEqual(result.returncode, 0, result.stderr)
        for port in (5901, 5902):
            self.assertIn(
                ["1", "serve", "--bg", f"--tcp={port}", f"tcp://127.0.0.1:{port}"],
                self.log("tailscale"),
            )
        result = self.run_script("access", "disable", "2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            ["1", "serve", "--bg", "--tcp=5902", "tcp://127.0.0.1:5902", "off"],
            self.log("tailscale"),
        )

    def test_recover_all_proceeds_when_one_session_fails(self):
        (self.root / "fail-pokeidle-session@1.service").touch()
        result = self.run_script("recover", "all")
        self.assertEqual(result.returncode, 1)
        self.assertIn(["1", "restart", "pokeidle-session@1.service"], self.log("systemctl"))
        self.assertIn(["1", "restart", "pokeidle-session@2.service"], self.log("systemctl"))
        self.assertIn("VNC local da sessão 2 disponível", result.stdout)
        self.assertEqual(self.run_script("recover", "3").returncode, 1)

    def test_chromium_health_accepts_expected_process(self):
        profile = self.root / "health-profile"
        profile.mkdir()
        process = subprocess.Popen(
            [str(self.bin_dir / "chromium"), f"--user-data-dir={profile}"],
            env=self.env(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        self.addCleanup(self.stop_process, process)
        self.wait_for(lambda: process.poll() is None)

        pid_file = self.root / "health.pid"
        pid_file.write_text(f"{process.pid}\n")
        pid_file.chmod(0o600)

        result = self.run_health(pid_file, profile)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("processo íntegro", result.stdout)

    def test_chromium_health_rejects_symlink_pid_file(self):
        target = self.root / "real.pid"
        target.write_text(f"{os.getpid()}\n")
        target.chmod(0o600)
        link = self.root / "linked.pid"
        link.symlink_to(target)

        result = self.run_health(link, self.root / "unused-profile")
        self.assertEqual(result.returncode, 1)
        self.assertIn("simbólico", result.stderr)

    def test_chromium_health_rejects_invalid_pid(self):
        pid_file = self.root / "invalid.pid"
        pid_file.write_text("not-a-pid\n")
        pid_file.chmod(0o600)

        result = self.run_health(pid_file, self.root / "unused-profile")
        self.assertEqual(result.returncode, 1)
        self.assertIn("PID inválido", result.stderr)

    def test_chromium_health_rejects_unexpected_profile(self):
        actual_profile = self.root / "actual-profile"
        actual_profile.mkdir()
        process = subprocess.Popen(
            [str(self.bin_dir / "chromium"), f"--user-data-dir={actual_profile}"],
            env=self.env(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        self.addCleanup(self.stop_process, process)
        self.wait_for(lambda: process.poll() is None)

        pid_file = self.root / "wrong-profile.pid"
        pid_file.write_text(f"{process.pid}\n")
        pid_file.chmod(0o600)

        result = self.run_health(pid_file, self.root / "expected-profile")
        self.assertEqual(result.returncode, 1)
        self.assertIn("perfil esperado", result.stderr)

    def test_doctor_reports_missing_forward(self):
        (self.root / "serve.json").write_text(
            json.dumps({"TCP": {"5901": {"TCPForward": "127.0.0.1:5901"}}})
        )
        result = self.run_script("doctor")
        self.assertIn("TCP 5901: encaminhamento privado configurado", result.stdout)
        self.assertIn("TCP 5902: encaminhamento privado ausente", result.stdout)
        self.assertEqual(result.returncode, 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
