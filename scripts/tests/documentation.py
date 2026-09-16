"""Check local Markdown links without contacting external services."""
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]


def anchors(text):
    counts = {}
    result = set()
    for heading in re.findall(r"^#{1,6}\s+(.+?)\s*#*\s*$", text, re.MULTILINE):
        slug = re.sub(r"[^\w\- ]", "", heading.lower()).replace(" ", "-")
        count = counts.get(slug, 0)
        counts[slug] = count + 1
        result.add(f"{slug}-{count}" if count else slug)
    return result


def main():
    paths = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT
    ).decode().split("\0")
    errors = []
    checked = 0
    for name in sorted(set(paths)):
        source = ROOT / name
        if source.suffix != ".md" or not source.is_file():
            continue
        text = re.sub(r"```.*?```", "", source.read_text(), flags=re.DOTALL)
        for link in re.findall(r"\]\(([^)]+)\)", text):
            url = urlsplit(link.strip("<>"))
            if url.scheme or url.netloc:
                continue
            target = (source.parent / unquote(url.path)).resolve() if url.path else source
            checked += 1
            if not target.exists():
                errors.append(f"{name}: missing {link}")
            elif url.fragment and target.suffix == ".md":
                if unquote(url.fragment) not in anchors(target.read_text()):
                    errors.append(f"{name}: missing anchor {link}")
    if errors:
        raise SystemExit("\n".join(errors))
    print(f"Documentation: {checked} local links/anchors checked.")


if __name__ == "__main__":
    main()
