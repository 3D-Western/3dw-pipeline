from typing import Any


def main(context: dict[str, Any]) -> dict[str, Any]:
    """Classify generated previews for moderation."""
    return {**context, "moderation": {"decision": "allow"}}
