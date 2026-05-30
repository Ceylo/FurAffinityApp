#!/usr/bin/env python3
"""Workspace-symbol search via sourcekit-lsp.

The editor/agent LSP `workspaceSymbol` operation is position-based and cannot
forward a query string, so it always asks sourcekit-lsp with an empty query and
gets nothing back. sourcekit-lsp itself fully supports `workspace/symbol`
(including cross-module FurAffinity <-> FAKit) as long as a non-empty query of
at least 3 characters is sent. This script drives sourcekit-lsp directly so that
workspace-wide symbol search works from the command line.

Usage:
    scripts/lsp-workspace-symbol.py <query> [--kind protocol|class|func|...]

Requires the project to have been built at least once (populated index store)
and buildServer.json present at the project root (see LSP_SETUP.md).
"""

import json
import os
import subprocess
import sys
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED_FILE = os.path.join(ROOT, "FAKit", "Sources", "FAKit", "FASession.swift")

# LSP SymbolKind -> readable name
KIND_NAMES = {
    1: "file", 2: "module", 3: "namespace", 4: "package", 5: "class",
    6: "method", 7: "property", 8: "field", 9: "constructor", 10: "enum",
    11: "interface", 12: "function", 13: "variable", 14: "constant",
    15: "string", 16: "number", 17: "boolean", 18: "array", 19: "object",
    20: "key", 21: "null", 22: "enum-member", 23: "struct", 24: "event",
    25: "operator", 26: "type-parameter",
}


def find_sourcekit_lsp() -> str:
    try:
        path = subprocess.check_output(
            ["xcrun", "--find", "sourcekit-lsp"], text=True
        ).strip()
        if path:
            return path
    except Exception:
        pass
    return "sourcekit-lsp"


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0

    query = sys.argv[1]
    if len(query) < 3:
        print("error: query must be at least 3 characters "
              "(sourcekit-lsp returns nothing for shorter queries)",
              file=sys.stderr)
        return 2

    kind_filter = None
    if "--kind" in sys.argv:
        kind_filter = sys.argv[sys.argv.index("--kind") + 1]

    proc = subprocess.Popen(
        [find_sourcekit_lsp()], cwd=ROOT,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )

    def send(msg):
        data = json.dumps(msg).encode()
        proc.stdin.write(f"Content-Length: {len(data)}\r\n\r\n".encode() + data)
        proc.stdin.flush()

    results = {}

    def reader():
        buf = b""
        while True:
            c = proc.stdout.read(1)
            if not c:
                break
            buf += c
            if buf.endswith(b"\r\n\r\n"):
                length = int(
                    [l for l in buf.split(b"\r\n")
                     if l.startswith(b"Content-Length")][0].split(b":")[1]
                )
                body = proc.stdout.read(length)
                try:
                    m = json.loads(body)
                    if isinstance(m.get("id"), int) and m["id"] == 99:
                        results["data"] = m.get("result") or []
                except Exception:
                    pass
                buf = b""

    threading.Thread(target=reader, daemon=True).start()

    root_uri = "file://" + ROOT
    send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "processId": os.getpid(), "rootUri": root_uri, "capabilities": {},
        "workspaceFolders": [{"uri": root_uri, "name": "FurAffinity"}],
    }})
    time.sleep(2)
    send({"jsonrpc": "2.0", "method": "initialized", "params": {}})

    # Opening a file gives sourcekit-lsp a build context and loads the index.
    if os.path.exists(SEED_FILE):
        with open(SEED_FILE) as fh:
            text = fh.read()
        send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {
            "textDocument": {"uri": "file://" + SEED_FILE, "languageId": "swift",
                             "version": 1, "text": text}}})
        time.sleep(3)

    send({"jsonrpc": "2.0", "id": 99, "method": "workspace/symbol",
          "params": {"query": query}})

    # Wait up to ~15s for the response (large result sets take a moment).
    for _ in range(150):
        if "data" in results:
            break
        time.sleep(0.1)
    proc.terminate()

    syms = results.get("data", [])
    if syms is None:
        syms = []

    rows = []
    for s in syms:
        kind = KIND_NAMES.get(s.get("kind"), str(s.get("kind")))
        if kind_filter and kind != kind_filter:
            continue
        loc = s.get("location", {})
        uri = loc.get("uri", "")
        path = uri.replace("file://", "").replace(ROOT + "/", "")
        line = loc.get("range", {}).get("start", {}).get("line", 0) + 1
        container = s.get("containerName", "")
        name = f"{container}.{s['name']}" if container else s["name"]
        rows.append((kind, name, f"{path}:{line}"))

    if not rows:
        print(f"No symbols found for query {query!r}"
              + (f" of kind {kind_filter!r}" if kind_filter else ""))
        return 0

    print(f"{len(rows)} symbol(s) for {query!r}:\n")
    for kind, name, loc in rows[:200]:
        print(f"  [{kind:11}] {name}")
        print(f"  {'':13} {loc}")
    if len(rows) > 200:
        print(f"\n  ... {len(rows) - 200} more (narrow the query or use --kind)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
