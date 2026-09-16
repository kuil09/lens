"""Bound CI tests, preserve their exit status, and diagnose only our process group."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


class Cancelled(Exception):
    def __init__(self, signum):
        self.signum = signum


def process_rows(text, group):
    rows = []
    for line in text.splitlines():
        fields = line.split(None, 6)
        if len(fields) == 7 and fields[0].isdigit() and fields[2] == str(group):
            # Never emit command arguments, environment, or full executable paths.
            rows.append(" ".join(fields[:6] + [Path(fields[6]).name]))
    return rows


def diagnose(group):
    try:
        result = subprocess.run(
            ["ps", "-axo", "pid=,ppid=,pgid=,stat=,etime=,pcpu=,comm="],
            capture_output=True, text=True, timeout=5, check=True)
        print("Test processes: PID PPID PGID STATE ELAPSED CPU EXECUTABLE", flush=True)
        for row in process_rows(result.stdout, group):
            print(row, flush=True)
    except (OSError, subprocess.SubprocessError):
        print("Test process metadata unavailable.", flush=True)


def monitor(process, *, timeout=480, interval=30, clock=time.monotonic,
            diagnostics=diagnose, report=print):
    start = clock()
    next_diagnostic = 180
    while True:
        status = process.poll()
        if status is not None:
            report(f"Test command finished after {clock() - start:.1f}s; exit={status}.", flush=True)
            return status if status >= 0 else 128 - status
        elapsed = clock() - start
        if elapsed >= timeout:
            report(f"::error::Test command exceeded {timeout}s; signing must not proceed.", flush=True)
            diagnostics(process.pid)
            return 124
        try:
            process.wait(timeout=min(interval, timeout - elapsed))
        except subprocess.TimeoutExpired:
            elapsed = clock() - start
            report(f"Tests still running: {elapsed:.0f}s elapsed; limit {timeout}s.", flush=True)
            if elapsed >= next_diagnostic:
                diagnostics(process.pid)
                next_diagnostic = elapsed + 60


def stop_group(process, grace=5):
    # start_new_session below makes this group private to this invocation.
    for signum in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, signum)
        except ProcessLookupError:
            break
        if signum == signal.SIGTERM:
            try:
                process.wait(timeout=grace)
            except subprocess.TimeoutExpired:
                pass
    process.wait(timeout=grace)


def run(command, *, cwd=None, timeout=480, interval=30, diagnostics=diagnose):
    env = dict(os.environ, NSUnbufferedIO="YES", LENS_TEST_INSTALLED_LANGUAGES="0",
               LENS_TEST_WINDOWSERVER="0")
    process = subprocess.Popen(command, cwd=cwd, env=env, start_new_session=True)
    previous = {}

    def cancel(signum, _frame):
        raise Cancelled(signum)

    try:
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous[signum] = signal.signal(signum, cancel)
        print(f"Starting CI tests: pid={process.pid}; hard limit={timeout}s; no automatic retry.", flush=True)
        return monitor(process, timeout=timeout, interval=interval, diagnostics=diagnostics)
    except Cancelled as error:
        print("CI tests canceled; terminating owned test processes.", flush=True)
        return 128 + error.signum
    finally:
        # Do not let a second runner signal interrupt bounded child cleanup.
        for signum in previous:
            signal.signal(signum, signal.SIG_IGN)
        try:
            stop_group(process)
        finally:
            for signum, handler in previous.items():
                signal.signal(signum, handler)


if __name__ == "__main__":
    if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted":
        sys.exit("Use this wrapper only on a GitHub-hosted CI runner.")
    sys.exit(run(["make", "test"], cwd=Path(__file__).resolve().parents[1]))
