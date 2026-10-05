"""Validate mirrored documentation and local Markdown links."""

from pathlib import Path
import re


def structure(text):
    """Purpose: Read mirror structure. Inputs: text. Returns: tuple. Side effects: None. Notes: Ignores translated wording."""
    blocks = re.findall(r"```[^\n]*\n.*?```", text, re.S)
    prose = re.sub(r"```[^\n]*\n.*?```", "", text, flags=re.S)
    headings = re.findall(r"^(#+) ", prose, re.M)
    tables = [line for line in prose.splitlines() if line.startswith("|")]
    return headings, len(tables), blocks


def main():
    """Purpose: Validate docs. Inputs: None. Returns: None. Side effects: Reads files. Notes: Raises on drift or broken links."""
    root = Path(__file__).resolve().parents[1]
    english = root / "doc/en-us"
    chinese = root / "doc/zh-cn"
    paths = {p.relative_to(english) for p in english.rglob("*.md")}
    other = {p.relative_to(chinese) for p in chinese.rglob("*.md")}
    if not paths or paths != other:
        raise ValueError(f"Documentation paths differ: {paths ^ other}")
    for relative in sorted(paths):
        if structure((english / relative).read_text()) != structure(
            (chinese / relative).read_text()
        ):
            raise ValueError(f"Documentation structure differs: {relative}")
    for path in [root / "README.md", *root.glob("doc/*/*.md")]:
        for link in re.findall(r"\]\(([^)]+)\)", path.read_text()):
            target = link.split("#", 1)[0]
            if target and not re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:", target):
                if not (path.parent / target).exists():
                    raise ValueError(f"Broken link in {path.relative_to(root)}: {link}")
    print(f"Documentation verified: {len(paths)} pages per language")


if __name__ == "__main__":
    main()
