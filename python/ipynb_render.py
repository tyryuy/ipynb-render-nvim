#!/usr/bin/env python3
import sys
import nbformat

def ipynb_to_view_lines(path: str) -> list[str]:
    nb = nbformat.read(path, as_version=4)

    lines: list[str] = []
    for i, cell in enumerate(nb.cells):
        ctype = cell.get("cell_type", "unknown")
        lines.append(f"# ==== Cell {i} ({ctype}) ====")

        if ctype == "markdown":
            src = cell.get("source", "")
            lines.extend(src.rstrip("\n").splitlines())
        elif ctype == "code":
            src = cell.get("source", "")
            lines.append("```")
            lines.extend(src.rstrip("\n").splitlines())
            lines.append("```")

            for o in cell.get("outputs", []):
                ot = o.get("output_type")
                if ot == "stream":
                    lines.append("---- output (stream) ----")
                    text = o.get("text", "")
                    if isinstance(text, list):
                        text = "".join(text)
                    lines.extend(str(text).rstrip("\n").splitlines())
                elif ot in ("execute_result", "display_data"):
                    data = o.get("data", {})
                    if "text/plain" in data:
                        lines.append("---- output (text/plain) ----")
                        t = data["text/plain"]
                        if isinstance(t, list):
                            t = "".join(t)
                        lines.extend(str(t).rstrip("\n").splitlines())
                elif ot == "error":
                    lines.append("---- output (error) ----")
                    lines.extend(o.get("traceback", []))
        else:
            src = cell.get("source", "")
            lines.extend(src.rstrip("\n").splitlines())

        lines.append("")  # blank line between cells
    return lines

def main():
    if len(sys.argv) < 2:
        print("usage: ipynb_render.py path/to/notebook.ipynb", file=sys.stderr)
        return 2
    path = sys.argv[1]
    for line in ipynb_to_view_lines(path):
        print(line)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
