"""Paths other tools key by this repo's location, for cleanup-worktree.py and
iOS/seed-source-packages.py."""
import hashlib
from pathlib import Path

DERIVED_DATA = Path.home() / "Library/Developer/Xcode/DerivedData"


def derived_data_hash(path):
    """The suffix Xcode gives a DerivedData directory: md5 of the project's absolute
    path, each 8-byte half a big-endian integer written as 14 letters a–z."""
    digest = hashlib.md5(str(path).encode()).digest()
    out = ""
    for half in (digest[:8], digest[8:]):
        n, letters = int.from_bytes(half, "big"), ""
        for _ in range(14):
            n, r = divmod(n, 26)
            letters = chr(ord("a") + r) + letters
        out += letters
    return out
