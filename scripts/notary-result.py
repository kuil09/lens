"""Validate notarytool output; never emit credentials or unrestricted service logs."""
import json
import re
import sys
from pathlib import Path


def submission_id(value):
    identifier = value.get("id", "")
    if not isinstance(identifier, str) or not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", identifier):
        raise ValueError("Missing or invalid notarization submission ID")
    return identifier


def accepted(value, expected=None):
    identifier = submission_id(value)
    if expected is not None and identifier != expected:
        raise ValueError("Notarization submission ID changed")
    if value.get("status") != "Accepted":
        raise ValueError("Notarization is not Accepted; do not upload a deliverable")
    return identifier


def signing_identity(text, team):
    matches = re.findall(r'\b([A-Fa-f0-9]{40}) "Developer ID Application: [^"\n]+ \(' + re.escape(team) + r'\)"', text)
    if len(matches) != 1:
        raise ValueError("Expected exactly one valid Developer ID Application identity for the configured team")
    return matches[0]


def main(args):
    command = args[0]
    if command == "identity":
        print(signing_identity(sys.stdin.read(), args[1]))
    elif command in ("id", "accepted"):
        value = json.loads(Path(args[1]).read_text())
        print(submission_id(value) if command == "id" else accepted(value, args[2]))
    elif command == "provenance":
        app = json.loads(Path(args[3]).read_text())
        dmg = json.loads(Path(args[4]).read_text())
        result = {"commit": args[2], "artifact": args[5], "appSubmission": accepted(app),
                  "dmgSubmission": accepted(dmg), "status": "Accepted", "bundleIdentifier": "dev.local.lens"}
        Path(args[1]).write_text(json.dumps(result, indent=2) + "\n")
    else:
        raise ValueError("Unknown command")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (ValueError, KeyError, IndexError, OSError):
        sys.exit("Notarization metadata validation failed; no deliverable is approved.")
