#!/usr/bin/env python3
import json
import sys
import nbformat

def read_notebook(path: str) -> None:
    nb = nbformat.read(path, as_version=4)
    print(json.dumps(nb, ensure_ascii=False))

def write_notebook(path: str) -> int:
    data = sys.stdin.read()
    if not data:
        print("no input", file=sys.stderr)
        return 2
    obj = json.loads(data)
    nb = nbformat.from_dict(obj)
    nbformat.write(nb, path)
    return 0

def main() -> int:
    if len(sys.argv) < 3:
        print("usage: ipynb_render.py [read|write] path/to/notebook.ipynb", file=sys.stderr)
        return 2
    mode = sys.argv[1]
    path = sys.argv[2]

    if mode == "read":
        read_notebook(path)
        return 0
    if mode == "write":
        return write_notebook(path)

    print("unknown mode", file=sys.stderr)
    return 2

if __name__ == "__main__":
    raise SystemExit(main())
