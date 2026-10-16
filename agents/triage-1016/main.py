"""Triage agent: labels new issues and routes them. Throwaway agent for the link-agent skill test; safe to delete."""
from pathlib import Path

SYSTEM_PROMPT = (Path(__file__).parent / "prompts" / "system.md").read_text()
SKILLS = ["config-new-1015"]  # loaded from skills/config-new-1015


def run(issue: str) -> str:
    return f"{SYSTEM_PROMPT}\n\nIssue:\n{issue}"
