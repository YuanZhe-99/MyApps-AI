"""Verify that backend-neutral packages do not resolve concrete AI backends."""

from pathlib import Path
import json
import subprocess

# Packages that must stay free of native plugins and concrete backends.
NEUTRAL = ["myapps_ai_core", "myapps_ai", "myapps_ai_models", "myapps_ai_llm", "myapps_ai_asr", "myapps_ai_online", "myapps_ai_ui", "myapps_ai_local_ui", "myapps_ai_online_ui"]
FORBIDDEN_PREFIXES = ("myapps_ai_platform", "myapps_ai_asr_", "myapps_ai_llm_")


def closure(package_dir):
    """Purpose: Resolve a package's dependency closure. Inputs: package_dir. Returns: set of names. Side effects: Runs flutter pub deps. Notes: Requires a prior pub get."""
    result = subprocess.run(["flutter", "pub", "deps", "--json"], cwd=package_dir,
                            check=True, capture_output=True, text=True)
    text = result.stdout[result.stdout.index("{"):]
    return {entry["name"] for entry in json.loads(text)["packages"]}


def main():
    """Purpose: Fail on forbidden dependencies. Inputs: None. Returns: None. Side effects: Runs pub commands. Notes: Raises on violation."""
    root = Path(__file__).resolve().parents[1] / "packages"
    for name in NEUTRAL:
        package_dir = root / name
        subprocess.run(["flutter", "pub", "get"], cwd=package_dir, check=True,
                       capture_output=True)
        found = sorted(d for d in closure(package_dir) - {name}
                       if d.startswith(FORBIDDEN_PREFIXES))
        if found:
            raise ValueError(f"{name} resolves concrete backends: {found}")
        pubspec = (package_dir / "pubspec.yaml").read_text()
        if "\n  plugin:" in pubspec:
            raise ValueError(f"{name} declares a Flutter plugin")
    print(f"Dependency isolation verified: {', '.join(NEUTRAL)}")


if __name__ == "__main__":
    main()
