"""Run the existing pure-domain XCTest sources on the host, without iOS.

Source membership comes from project.yml so CI and Xcode use the same tests.
The generated package is temporary and has no third-party dependencies.
"""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def domain_sources():
    spec = (ROOT / "project.yml").read_text()
    target = spec.split("  ProbablyGroceriesPredictionTests:\n", 1)[1]
    source_block = target.split("    sources:\n", 1)[1].split("    dependencies:", 1)[0]
    sources = re.findall(r"^      - (.+\.swift)$", source_block, re.MULTILINE)
    if not sources or len({Path(p).name for p in sources}) != len(sources):
        raise ValueError("Missing or colliding domain sources")
    for path in sources:
        if not (ROOT / path).is_file():
            raise FileNotFoundError(path)
    return sources


def main():
    with tempfile.TemporaryDirectory(prefix="groceries-domain-") as directory:
        package = Path(directory)
        tests = package / "Tests"
        tests.mkdir()
        for path in domain_sources():
            shutil.copy2(ROOT / path, tests / Path(path).name)
        (package / "Package.swift").write_text(
            '// swift-tools-version: 5.9\n'
            'import PackageDescription\n'
            'let package = Package(name: "GroceriesDomain", '
            'platforms: [.macOS(.v13)], '
            'targets: [.testTarget(name: "DomainTests", path: "Tests")], '
            'swiftLanguageVersions: [.v5])\n'
        )
        subprocess.run(["swift", "test", "--package-path", str(package), "--jobs", "2"], check=True)


if __name__ == "__main__":
    main()
