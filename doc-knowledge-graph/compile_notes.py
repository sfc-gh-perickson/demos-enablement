#!/usr/bin/env python3
"""
Compile concept note markdown files into a JSON manifest for Snowflake ingestion.

Usage:
    python compile_notes.py notes/ > notes_manifest.json

Each markdown file must have YAML frontmatter delimited by '---' lines.
Required frontmatter fields: slug, title, kind
Optional: see_also, applicable_orgs
"""

import json
import sys
from pathlib import Path

import yaml


def parse_note(filepath: Path) -> dict:
    """Parse a markdown file with YAML frontmatter into a manifest entry."""
    content = filepath.read_text(encoding="utf-8")

    if not content.startswith("---"):
        raise ValueError(f"{filepath}: missing YAML frontmatter (must start with ---)")

    # Split on the second '---' delimiter
    parts = content.split("---", 2)
    if len(parts) < 3:
        raise ValueError(f"{filepath}: malformed frontmatter (missing closing ---)")

    frontmatter = yaml.safe_load(parts[1])
    body = parts[2].strip()

    # Validate required fields
    for field in ("slug", "title", "kind"):
        if field not in frontmatter:
            raise ValueError(f"{filepath}: missing required frontmatter field '{field}'")

    return {
        "slug": frontmatter["slug"],
        "title": frontmatter["title"],
        "kind": frontmatter["kind"],
        "body_markdown": body,
        "frontmatter": frontmatter,
        "see_also": frontmatter.get("see_also") or [],
        "applicable_orgs": frontmatter.get("applicable_orgs") or [],
    }


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <notes_directory>", file=sys.stderr)
        sys.exit(1)

    notes_dir = Path(sys.argv[1])
    if not notes_dir.is_dir():
        print(f"Error: {notes_dir} is not a directory", file=sys.stderr)
        sys.exit(1)

    notes = []
    errors = []

    for filepath in sorted(notes_dir.glob("*.md")):
        try:
            note = parse_note(filepath)
            notes.append(note)
        except Exception as e:
            errors.append(str(e))

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        sys.exit(1)

    print(f"Compiled {len(notes)} notes", file=sys.stderr)
    json.dump(notes, sys.stdout, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main()
