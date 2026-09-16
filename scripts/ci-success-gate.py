"""Require successful trusted CI for the exact signing SHA; never dispatch or retry."""
import json
import os
import re
import subprocess
import sys

REPOSITORY = "kuil09/lens"
WORKFLOW_PATH = ".github/workflows/ci.yml"


class GateError(Exception):
    pass


def api(path, *, paginate=False):
    command = ["gh", "api", path]
    if paginate:
        command += ["--paginate", "--slurp"]
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=True, timeout=45)
        return json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, ValueError):
        # Raw HTTP/process errors are not needed and might contain credentials.
        raise GateError("Cannot verify CI history; signing is blocked.") from None


def require_success(sha, fetch=api):
    if not re.fullmatch(r"[a-f0-9]{40}", sha):
        raise GateError("Invalid source SHA.")
    workflow = fetch(f"repos/{REPOSITORY}/actions/workflows/ci.yml")
    if (workflow.get("path") != WORKFLOW_PATH or workflow.get("state") != "active"
            or type(workflow.get("id")) is not int):
        raise GateError("Expected active Lens CI workflow is unavailable.")
    pages = fetch(f"repos/{REPOSITORY}/actions/workflows/{workflow['id']}/runs"
                  f"?head_sha={sha}&branch=main&event=push&status=success&per_page=100", paginate=True)
    for page in pages:
        for run in page["workflow_runs"]:
            # Validate returned fields too; filters alone are not the security boundary.
            if (run.get("head_sha") == sha and run.get("head_branch") == "main"
                    and run.get("event") == "push" and run.get("status") == "completed"
                    and run.get("conclusion") == "success" and run.get("workflow_id") == workflow["id"]
                    and run.get("path") == WORKFLOW_PATH
                    and (run.get("repository") or {}).get("full_name") == REPOSITORY
                    and (run.get("head_repository") or {}).get("full_name") == REPOSITORY
                    and type(run.get("id")) is int and run["id"] > 0):
                return run["id"]
    raise GateError("No completed successful main-push Lens CI for this exact SHA; signing is blocked.")


def main():
    if (os.environ.get("GITHUB_REPOSITORY") != REPOSITORY
            or os.environ.get("GITHUB_REF") != "refs/heads/main"
            or os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch"):
        raise GateError("Only the main-branch signing dispatch may use this gate.")
    sha = os.environ.get("GITHUB_SHA", "")
    head = subprocess.run(["git", "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()
    if head != sha:
        raise GateError("Checkout differs from the signing SHA.")
    run_id = require_success(sha)
    print(f"Verified successful CI for {sha}: https://github.com/{REPOSITORY}/actions/runs/{run_id}")


if __name__ == "__main__":
    try:
        main()
    except (GateError, KeyError, TypeError, AttributeError, subprocess.SubprocessError, OSError) as error:
        message = str(error) if isinstance(error, GateError) else "Invalid CI evidence; signing is blocked."
        sys.exit(message)
