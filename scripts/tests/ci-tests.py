"""Synthetic watchdog tests; no Swift, capture, signing, or service credentials."""
import importlib.util
import contextlib
import io
import os
from pathlib import Path
import signal
import select
import shlex
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("watchdog", ROOT / "scripts/ci-tests.py")
watchdog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watchdog)


class FakeProcess:
    pid = 4321

    def __init__(self, finish=None, status=0):
        self.now = 0
        self.finish = finish
        self.status = status

    def poll(self):
        return self.status if self.finish is not None and self.now >= self.finish else None

    def wait(self, timeout):
        if self.finish is not None and self.finish <= self.now + timeout:
            self.now = self.finish
            return self.status
        self.now += timeout
        raise subprocess.TimeoutExpired("synthetic", timeout)


class WatchdogTests(unittest.TestCase):
    def test_ci_triggers_only_main_push_pr_and_manual(self):
        text = (ROOT / ".github/workflows/ci.yml").read_text()
        triggers = text.split("on:\n", 1)[1].split("\npermissions:", 1)[0]
        self.assertEqual(triggers.strip(), "push:\n    branches: [main]\n  pull_request:\n  workflow_dispatch:")
        self.assertNotIn("paths-ignore", text)

    def test_shared_test_entrypoint_serializes_without_filtering(self):
        script = (ROOT / "scripts/lens.sh").read_text()
        commands = [shlex.split(line) for line in script.splitlines() if " swift test " in line]
        self.assertEqual(len(commands), 1)
        command = commands[0]
        self.assertIn("--no-parallel", command)
        self.assertNotIn("--parallel", command)
        self.assertNotIn("--filter", command)
        self.assertNotIn("--skip", command)
        self.assertIn("LENS_TEST_INSTALLED_LANGUAGES=$INSTALLED", command)

    def test_success_failure_and_signal_status_are_preserved(self):
        for code, expected in [(0, 0), (7, 7), (-15, 143)]:
            process = FakeProcess(finish=3, status=code)
            self.assertEqual(watchdog.monitor(process, clock=lambda: process.now,
                report=lambda *a, **k: None), expected)

    def test_hang_has_heartbeats_diagnostics_and_bounded_deadline(self):
        process = FakeProcess()
        messages, samples = [], []
        result = watchdog.monitor(process, clock=lambda: process.now,
            diagnostics=samples.append, report=lambda text, **kw: messages.append(text))
        self.assertEqual(result, 124)
        self.assertEqual(process.now, 480)
        self.assertEqual(len([m for m in messages if "still running" in m]), 16)
        self.assertTrue(samples)
        self.assertEqual(set(samples), {process.pid})

    def test_process_diagnostics_exclude_unrelated_group_and_paths(self):
        text = "1 0 1 S 00:01 0.0 /private/other\n42 1 42 S 00:09 0.1 /private/build/swiftpm-testing\n"
        self.assertEqual(watchdog.process_rows(text, 42), ["42 1 42 S 00:09 0.1 swiftpm-testing"])

    def test_real_child_exit_and_timeout(self):
        # Expected watchdog errors must not become false GitHub error annotations.
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(watchdog.run([sys.executable, "-c", "raise SystemExit(7)"],
                timeout=3, interval=1, diagnostics=lambda _: None), 7)
            self.assertEqual(watchdog.run([sys.executable, "-c", "import signal; signal.pause()"],
                timeout=0.2, interval=0.1, diagnostics=lambda _: None), 124)

    def test_real_sigterm_reaps_owned_child(self):
        code = (f"import runpy,sys; w=runpy.run_path({str(ROOT / 'scripts/ci-tests.py')!r}); "
                "sys.exit(w['run']([sys.executable,'-c','import signal; signal.pause()'], "
                "timeout=5, diagnostics=lambda _:None))")
        wrapper = subprocess.Popen([sys.executable, "-u", "-c", code], stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True)
        try:
            self.assertTrue(select.select([wrapper.stdout], [], [], 5)[0], "No startup handshake")
            line = wrapper.stdout.readline()
            self.assertIn("Starting CI tests: pid=", line)
            child = int(line.split("pid=", 1)[1].split(";", 1)[0])
            wrapper.send_signal(signal.SIGTERM)
            wrapper.communicate(timeout=7)
            self.assertEqual(wrapper.returncode, 143)
            with self.assertRaises(ProcessLookupError):
                os.kill(child, 0)
        finally:
            if wrapper.poll() is None:
                wrapper.send_signal(signal.SIGTERM)
                wrapper.communicate(timeout=10)

    def test_cancel_cleans_group_and_restores_handlers(self):
        process = FakeProcess()
        before = signal.getsignal(signal.SIGTERM)
        with contextlib.redirect_stdout(io.StringIO()), \
             patch.object(watchdog.subprocess, "Popen", return_value=process) as launch, \
             patch.object(watchdog, "monitor", side_effect=watchdog.Cancelled(signal.SIGTERM)), \
             patch.object(watchdog, "stop_group") as stop:
            self.assertEqual(watchdog.run(["synthetic"]), 143)
            stop.assert_called_once_with(process)
            self.assertTrue(launch.call_args.kwargs["start_new_session"])
            self.assertEqual(launch.call_args.kwargs["env"]["LENS_TEST_INSTALLED_LANGUAGES"], "0")
        self.assertEqual(signal.getsignal(signal.SIGTERM), before)

    def test_group_cleanup_kills_remaining_children_after_parent_exits(self):
        process = FakeProcess(finish=0)
        with patch.object(watchdog.os, "killpg") as kill:
            watchdog.stop_group(process)
        self.assertEqual([call.args for call in kill.call_args_list],
                         [(4321, signal.SIGTERM), (4321, signal.SIGKILL)])

    def test_workflows_bound_tests_without_bypassing_failure(self):
        for name in ["ci.yml"]:
            text = (ROOT / ".github/workflows" / name).read_text()
            self.assertIn("timeout-minutes: 10", text)
            self.assertIn("run: python3 -u scripts/ci-tests.py", text)
            self.assertNotIn("continue-on-error", text)
        text = (ROOT / ".github/workflows/notarized-dmg.yml").read_text()
        self.assertNotIn("scripts/ci-tests.py", text)
        self.assertIn("needs: verify-ci", text)


if __name__ == "__main__":
    unittest.main()
