#!/usr/bin/env python3
"""Check a pull request against CONTRIBUTING.md.

Standard library only. Checks that the title and every commit are Conventional
Commits, that a breaking change carries both `!` and a `BREAKING CHANGE:`
footer, and that the description fills in the template's required sections.

    python3 .github/scripts/check_pull_request.py "$GITHUB_EVENT_PATH"

It reads the pull request from the event file and the commits with git, so no
pull request text passes through the shell.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

TYPES = ("feat", "fix", "docs", "test", "refactor", "perf", "build", "ci", "chore", "revert")
SUBJECT_RE = re.compile(r"^(?P<type>[a-z]+)(\((?P<scope>[a-z0-9][a-z0-9-]*)\))?(?P<breaking>!)?: \S")
FOOTER_RE = re.compile(r"^BREAKING[ -]CHANGE: \S", re.MULTILINE)
COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)
HEADING_RE = re.compile(r"^##[ \t]+(.+?)[ \t]*$", re.MULTILINE)
REQUIRED_SECTIONS = ("What changed", "Why", "How it was verified")
GUIDE = "See the Pull requests section of CONTRIBUTING.md."


def check_subject(subject: str, what: str) -> list[str]:
    match = SUBJECT_RE.match(subject)
    if subject.startswith(("fixup!", "squash!", "amend!")):
        return [f"{what} is a {subject.split('!')[0]} commit: squash it into the commit it fixes."]
    if match is None:
        return [
            f'{what} "{subject}" isn\'t a Conventional Commit. Write it as '
            "<type>(<optional-scope>): <summary>, such as \"fix(cli): keep local edits on remove\"."
        ]
    if match["type"] not in TYPES:
        return [f'{what} uses the type "{match["type"]}". Use one of: {", ".join(TYPES)}.']
    return []


def check_commit(sha: str, message: str) -> list[str]:
    subject = message.split("\n", 1)[0].strip()
    what = f"Commit {sha[:7]}"
    problems = check_subject(subject, what)
    if problems:
        return problems
    breaking = SUBJECT_RE.match(subject)["breaking"] is not None
    footer = FOOTER_RE.search(message) is not None
    if breaking and not footer:
        return [f"{what} is marked breaking with `!` but has no `BREAKING CHANGE:` footer saying what breaks."]
    if footer and not breaking:
        return [f"{what} has a `BREAKING CHANGE:` footer, so its subject needs `!`, such as \"feat(cli)!: ...\"."]
    return []


def sections(body: str) -> dict[str, str]:
    text = COMMENT_RE.sub("", body)
    found = list(HEADING_RE.finditer(text))
    out = {}
    for i, heading in enumerate(found):
        end = found[i + 1].start() if i + 1 < len(found) else len(text)
        out[heading[1].lower()] = text[heading.end():end].strip()
    return out


def check_body(body: str | None) -> list[str]:
    found = sections(body or "")
    problems = []
    for name in REQUIRED_SECTIONS:
        if name.lower() not in found:
            problems.append(f'The description has no "## {name}" section. Start from the pull request template.')
        elif not found[name.lower()]:
            problems.append(f'Fill in the "## {name}" section of the description.')
    return problems


def commits(base: str, head: str) -> list[tuple[str, str]]:
    out = subprocess.run(
        ["git", "log", "--no-merges", "--format=%H%x00%B%x1e", f"{base}..{head}"],
        check=True, capture_output=True, text=True,
    ).stdout
    entries = []
    for record in out.split("\x1e"):
        record = record.strip("\n")
        if record:
            sha, _, message = record.partition("\x00")
            entries.append((sha, message))
    return entries


def check_pull_request(event: dict, history: list[tuple[str, str]]) -> list[str]:
    pr = event["pull_request"]
    problems = check_subject(pr["title"].strip(), "The title")
    for sha, message in history:
        problems += check_commit(sha, message)
    if pr["user"]["type"] != "Bot":
        problems += check_body(pr.get("body"))
    return problems


def annotation(message: str) -> str:
    """Escape a message the way GitHub's toolkit does, so commit text can't start another workflow command."""
    return message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def main() -> int:
    event = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    pr = event["pull_request"]
    problems = check_pull_request(event, commits(pr["base"]["sha"], pr["head"]["sha"]))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    for problem in problems:
        print(f"::error title=Pull request::{annotation(problem)}")
    if summary:
        with open(summary, "a", encoding="utf-8") as out:
            if problems:
                out.write("### Fix these before review\n\n" + "".join(f"- {p}\n" for p in problems) + f"\n{GUIDE}\n")
            else:
                out.write("The title, commits and description follow CONTRIBUTING.md.\n")
    if problems:
        print(f"{len(problems)} problem(s). {GUIDE}")
        return 1
    print("The title, commits and description follow CONTRIBUTING.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
