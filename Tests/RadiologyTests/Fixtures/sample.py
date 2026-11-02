"""Module docstring — 放射線."""
from dataclasses import dataclass
import os

MAX_SCANS = 10
DEFAULT_TITLE = "胸部"


@dataclass
class Scan:
    """A scan."""

    title: str
    count: int = 0

    def render(self) -> str:
        parts = [self.title]
        for index in range(self.count):
            parts.append(str(index))
        if not parts:
            return ""
        return ",".join(parts)


async def load(path: str) -> Scan:
    with open(path) as handle:
        text = handle.read()
    try:
        return Scan(title=text, count=len(text))
    except ValueError as error:
        raise RuntimeError("bad") from error


doubler = lambda x: x * 2
