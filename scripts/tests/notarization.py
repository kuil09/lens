"""Fail-closed checks; fake credentials only, no Keychain or Apple requests."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("notary", ROOT / "scripts/notary-result.py")
notary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notary)
ID = "12345678-1234-1234-1234-123456789abc"


class NotaryMetadataTests(unittest.TestCase):
    def test_only_accepted_matching_submission_is_approved(self):
        self.assertEqual(notary.accepted({"id": ID, "status": "Accepted"}, ID), ID)
        for status in ["In Progress", "Invalid", "Rejected", "accepted", None]:
            with self.subTest(status=status), self.assertRaises(ValueError):
                notary.accepted({"id": ID, "status": status}, ID)
        with self.assertRaises(ValueError):
            notary.accepted({"id": ID, "status": "Accepted"}, "different")

    def test_missing_or_malformed_id_is_rejected(self):
        for value in [{}, {"id": None}, {"id": "../other-file"}, {"id": ""}]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                notary.submission_id(value)

    def test_identity_requires_exactly_one_application_certificate_for_team(self):
        certificate = '1) ' + 'A' * 40 + ' "Developer ID Application: Example (ABCDEFGHIJ)"'
        self.assertEqual(notary.signing_identity(certificate, "ABCDEFGHIJ"), "A" * 40)
        for text in ["", certificate * 2, certificate.replace("Application:", "Installer:"),
                     certificate.replace("ABCDEFGHIJ", "ZZZZZZZZZZ")]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                notary.signing_identity(text, "ABCDEFGHIJ")

    def test_provenance_copies_only_allowlisted_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            source = path / "result.json"
            source.write_text(json.dumps({"id": ID, "status": "Accepted", "password": "FAKE-SECRET"}))
            output = path / "provenance.json"
            notary.main(["provenance", str(output), "a" * 40, str(source), str(source), "Lens.dmg"])
            self.assertNotIn("FAKE-SECRET", output.read_text())
            self.assertEqual(json.loads(output.read_text())["appSubmission"], ID)


class SigningPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.env = {"PATH": os.environ["PATH"], "GITHUB_ACTIONS": "true",
                    "RUNNER_ENVIRONMENT": "github-hosted", "RUNNER_TEMP": self.temp.name,
                    "GITHUB_REPOSITORY": "kuil09/lens", "GITHUB_REF": "refs/heads/main",
                    "GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_SHA": "a" * 40,
                    "LENS_TEAM_ID": "ABCDEFGHIJ", "LENS_CERTIFICATE_P12_BASE64": "FAKE-CERT",
                    "LENS_CERTIFICATE_PASSWORD": "FAKE-PASSWORD", "LENS_APPLE_ID": "fake@example.invalid",
                    "LENS_APPLE_APP_PASSWORD": "FAKE-APP-PASSWORD"}

    def tearDown(self):
        self.temp.cleanup()

    def run_preflight(self, env):
        result = subprocess.run(["bash", str(ROOT / "scripts/ci-notarize.sh"), "preflight"],
                                env=env, capture_output=True, text=True)
        for secret in ["FAKE-CERT", "FAKE-PASSWORD", "fake@example.invalid", "FAKE-APP-PASSWORD"]:
            self.assertNotIn(secret, result.stdout + result.stderr)
        self.assertEqual(list(Path(self.temp.name).iterdir()), [])
        return result

    def test_complete_configuration_has_no_side_effects(self):
        self.assertEqual(self.run_preflight(self.env).returncode, 0)

    def test_every_missing_secret_fails_before_signing(self):
        for key in ["LENS_CERTIFICATE_P12_BASE64", "LENS_CERTIFICATE_PASSWORD", "LENS_APPLE_ID",
                    "LENS_APPLE_APP_PASSWORD", "LENS_TEAM_ID"]:
            env = self.env.copy()
            del env[key]
            with self.subTest(key=key):
                self.assertNotEqual(self.run_preflight(env).returncode, 0)

    def test_pull_requests_other_branches_forks_and_local_runs_cannot_sign(self):
        for key, value in [("GITHUB_REF", "refs/pull/1/merge"), ("GITHUB_REF", "refs/tags/v1"),
                           ("GITHUB_EVENT_NAME", "pull_request_target"), ("GITHUB_REPOSITORY", "someone/lens"),
                           ("RUNNER_ENVIRONMENT", "self-hosted"), ("GITHUB_ACTIONS", "false"),
                           ("GITHUB_SHA", "bad"), ("LENS_TEAM_ID", "bad")]:
            env = self.env.copy()
            env[key] = value
            with self.subTest(key=key, value=value):
                self.assertNotEqual(self.run_preflight(env).returncode, 0)

    def test_build_with_missing_secret_does_not_create_outputs(self):
        env = self.env.copy()
        del env["LENS_CERTIFICATE_PASSWORD"]
        result = subprocess.run(["bash", str(ROOT / "scripts/ci-notarize.sh"), "build"],
                                env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(Path(self.temp.name).iterdir()), [])


if __name__ == "__main__":
    unittest.main()
