"""CI evidence tests: no credentials, dispatches, signing, or network calls."""
import importlib.util
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("gate", ROOT / "scripts/ci-success-gate.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
SHA = "a" * 40
WORKFLOW = {"id": 123, "path": gate.WORKFLOW_PATH, "state": "active"}
RUN = {"id": 456, "workflow_id": 123, "path": gate.WORKFLOW_PATH,
       "head_sha": SHA, "head_branch": "main", "event": "push",
       "status": "completed", "conclusion": "success",
       "repository": {"full_name": gate.REPOSITORY},
       "head_repository": {"full_name": gate.REPOSITORY}}


def fetcher(runs, workflow=WORKFLOW):
    def fetch(path, **kwargs):
        if path.endswith("/ci.yml"):
            return workflow
        assert f"head_sha={SHA}" in path
        assert "branch=main&event=push&status=success" in path
        assert kwargs == {"paginate": True}
        return [{"workflow_runs": runs}]
    return fetch


class EvidenceTests(unittest.TestCase):
    def test_exact_trusted_success_is_accepted(self):
        self.assertEqual(gate.require_success(SHA, fetcher([RUN])), 456)

    def test_missing_or_non_success_history_is_rejected(self):
        for value in ["failure", "cancelled", "timed_out", "skipped", "neutral", None]:
            with self.subTest(value=value), self.assertRaises(gate.GateError):
                gate.require_success(SHA, fetcher([dict(RUN, conclusion=value)]))
        with self.assertRaises(gate.GateError):
            gate.require_success(SHA, fetcher([]))

    def test_wrong_commit_workflow_event_branch_or_repository_is_rejected(self):
        changes = {"head_sha": "b" * 40, "workflow_id": 999, "head_branch": "feature",
                   "event": "pull_request", "status": "in_progress", "id": "456",
                   "path": ".github/workflows/other.yml",
                   "repository": {"full_name": "fork/lens"},
                   "head_repository": {"full_name": "fork/lens"}}
        for key, value in changes.items():
            with self.subTest(key=key), self.assertRaises(gate.GateError):
                gate.require_success(SHA, fetcher([dict(RUN, **{key: value})]))

    def test_inactive_or_wrong_workflow_is_rejected(self):
        for change in [{"state": "disabled_manually"}, {"id": "123"}, {"path": "other.yml"}]:
            with self.assertRaises(gate.GateError):
                gate.require_success(SHA, fetcher([RUN], dict(WORKFLOW, **change)))

    def test_paginated_success_and_fresh_approval_recheck(self):
        def pages(path, **kwargs):
            return WORKFLOW if path.endswith("/ci.yml") else [
                {"workflow_runs": []}, {"workflow_runs": [RUN]}]
        self.assertEqual(gate.require_success(SHA, pages), 456)
        # A rerun can replace a prior successful conclusion while approval is pending.
        with self.assertRaises(gate.GateError):
            gate.require_success(SHA, fetcher([dict(RUN, status="queued", conclusion=None)]))

    def test_api_failure_and_invalid_json_fail_closed_without_raw_error(self):
        for failure in [subprocess.TimeoutExpired("gh", 45),
                        subprocess.CalledProcessError(1, "gh", stderr="sensitive"), OSError("sensitive")]:
            with patch.object(gate.subprocess, "run", side_effect=failure), self.assertRaises(gate.GateError) as error:
                gate.api("synthetic")
            self.assertNotIn("sensitive", str(error.exception))
        with patch.object(gate.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "bad-json")):
            with self.assertRaises(gate.GateError):
                gate.api("synthetic")

    def test_entrypoint_rejects_wrong_context_or_checkout_before_api(self):
        env = {"GITHUB_REPOSITORY": gate.REPOSITORY, "GITHUB_REF": "refs/heads/main",
               "GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_SHA": SHA}
        for key, value in [("GITHUB_REPOSITORY", "fork/lens"), ("GITHUB_REF", "refs/heads/dev"),
                           ("GITHUB_EVENT_NAME", "pull_request")]:
            with patch.dict(os.environ, dict(env, **{key: value}), clear=True), \
                 patch.object(gate, "require_success") as check, self.assertRaises(gate.GateError):
                gate.main()
            check.assert_not_called()
        with patch.dict(os.environ, env, clear=True), \
             patch.object(gate.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "b" * 40)), \
             patch.object(gate, "require_success") as check, self.assertRaises(gate.GateError):
            gate.main()
        check.assert_not_called()

    def test_workflow_checks_before_approval_and_before_secrets(self):
        text = (ROOT / ".github/workflows/notarized-dmg.yml").read_text()
        gate_job, signing_job = text.split("  notarized-dmg:", 1)
        self.assertNotIn("secrets.", gate_job)
        self.assertNotIn("environment: release-signing", gate_job)
        self.assertIn("needs: verify-ci", signing_job)
        self.assertIn("environment: release-signing", signing_job)
        self.assertLess(signing_job.index("scripts/ci-success-gate.py"), signing_job.index("secrets."))
        self.assertEqual(text.count("run: python3 scripts/ci-success-gate.py"), 2)
        self.assertEqual(text.count("ref: ${{ github.sha }}"), 2)
        for disallowed in ["make test", "make check", "continue-on-error", "actions: write", "contents: write"]:
            self.assertNotIn(disallowed, text)
        self.assertIn("actions: read", text)


if __name__ == "__main__":
    unittest.main()
