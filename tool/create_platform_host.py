"""Create an ephemeral Flutter host to compile and register the native plugin."""
from pathlib import Path
import subprocess
import sys


def main():
    """Purpose: Generate CI host. Inputs: destination. Returns: None. Side effects: Creates Flutter app. Notes: Destination must not exist."""
    root = Path(__file__).resolve().parents[1]
    host = Path(sys.argv[1]).resolve()
    if host.exists():
        raise ValueError("Host destination already exists")
    subprocess.run(["flutter", "create", "--platforms=android,ios,macos",
                    "--project-name=ai_platform_host", str(host)], check=True)
    pubspec = host / "pubspec.yaml"
    pubspec.write_text(pubspec.read_text().replace("dependencies:\n", "dependencies:\n"
        f"  myapps_ai_platform:\n    path: {root / 'packages/myapps_ai_platform'}\n", 1))
    gradle = host / "android/app/build.gradle.kts"
    gradle.write_text(gradle.read_text().replace("minSdk = flutter.minSdkVersion", "minSdk = 26"))
    (host / "lib/main.dart").write_text("import 'package:flutter/material.dart';\n"
        "void main() => runApp(const MaterialApp(home: Scaffold(body: Text('AI platform host'))));\n")


if __name__ == "__main__":
    main()
