"""Verify that a fresh application can resolve every package."""

from pathlib import Path
import shutil
import subprocess
import sys


def main():
    """Purpose: Resolve all packages from a new app. Inputs: target directory argument. Returns: None. Side effects: Creates the app and runs pub get. Notes: Resolution only; whisper and llama are never built together."""
    root = Path(__file__).resolve().parents[1] / "packages"
    target = Path(sys.argv[1])
    if target.exists():
        shutil.rmtree(target)
    subprocess.run(["flutter", "create", "--platforms=linux,android", "--project-name",
                    "consumer_check", str(target)], check=True, capture_output=True)
    pubspec = target / "pubspec.yaml"
    names = sorted(p.name for p in root.iterdir() if (p / "pubspec.yaml").exists())
    deps = "".join(f"  {n}:\n    path: {root / n}\n" for n in names)
    text = pubspec.read_text().replace("dependencies:\n", "dependencies:\n" + deps, 1)
    pubspec.write_text(text)
    subprocess.run(["flutter", "pub", "get"], cwd=target, check=True)
    print(f"Consumer resolution verified: {', '.join(names)}")


if __name__ == "__main__":
    main()
