'''
LOVR API documentation lookup tool for coding agents.

Data: lovr_docs.json, generated from lovr-docs v0.19.0 api/init.lua via lua_to_json.lua.

Usage:
  lovr_docs("lovr.graphics")            -- list module functions, objects, enums
  lovr_docs("lovr.graphics.newBuffer")  -- look up a module function
  lovr_docs("lovr.draw")                -- look up a callback
  lovr_docs("Pass")                     -- look up an object and list its methods
  lovr_docs("Pass:cube")                -- look up a method on an object
  lovr_docs("DrawStyle")                -- look up an enum
'''

from __future__ import annotations
import json, os
import ex6


JSON_PATH = os.path.join(os.path.dirname(__file__), "lovr_docs.json")

with open(JSON_PATH, "r", encoding="utf-8") as f:
    _DATA = json.load(f)

_BY_KEY: dict[str, tuple[str, dict]] = {}
for c in _DATA["callbacks"]:
    _BY_KEY[c["key"]] = ("fn", c)
for m in _DATA["modules"]:
    _BY_KEY[m["key"]] = ("module", m)
    for f in m["functions"]:
        _BY_KEY[f["key"]] = ("fn", f)
    for e in m["enums"]:
        _BY_KEY[e["key"]] = ("enum", e)
    for o in m["objects"]:
        _BY_KEY[o["key"]] = ("object", o)
        for f in o["methods"]:
            _BY_KEY[f["key"]] = ("fn", f)


def _sig(name: str, v: dict):
    args = ", ".join(
        f"{a['name']}: {a.get('type', '?')}" + (f" = {a['default']}" if "default" in a else "")
        for a in v["arguments"]
    )
    rets = ", ".join(f"{r['name']}: {r.get('type', '?')}" for r in v["returns"])
    return f"{name}({args})" + (f" -> {rets}" if rets else "")


def _fields(items: list, indent: str):
    lines = []
    for a in items:
        default = f" [default {a['default']}]" if "default" in a else ""
        lines.append(f"{indent}{a['name']} ({a.get('type', '?')}){default}: {a.get('description', '')}")
        if a.get("table"):
            lines += _fields(a["table"], indent + "  ")
    return lines


def _fmt_fn(fn: dict, verbosity: int):
    if verbosity == 0:
        return "\n".join([fn.get("summary", "")] + [_sig(fn["key"], v) for v in fn["variants"]])
    lines = [f"{fn['key']}: {fn.get('description', '')}"]
    for i, v in enumerate(fn["variants"]):
        lines.append(f"\nVariant {i + 1}: {_sig(fn['key'], v)}")
        if v.get("description"):
            lines.append(v["description"])
        if v["arguments"]:
            lines += ["  Arguments:"] + _fields(v["arguments"], "    ")
        if v["returns"]:
            lines += ["  Returns:"] + _fields(v["returns"], "    ")
    if fn.get("notes"):
        lines.append(f"\nNotes: {fn['notes']}")
    for ex in fn.get("examples", []):
        lines.append(f"\nExample: {ex.get('description', '')}\n{ex['code']}")
    if fn.get("related"):
        lines.append(f"\nRelated: {', '.join(fn['related'])}")
    return "\n".join(lines)


def _brief(fn: dict):
    return f"  {fn['name']} - {fn.get('summary', '')}"


def _fmt_module(m: dict, verbosity: int):
    lines = [f"{m['key']}: {m.get('summary', '')}"]
    if verbosity and m.get("description"):
        lines.append(m["description"])
    if m["name"] == "lovr":
        lines += ["Callbacks:"] + [_brief(c) for c in _DATA["callbacks"]]
        lines += ["Modules:"] + [f"  {x['key']} - {x.get('summary', '')}" for x in _DATA["modules"] if x is not m]
    if m["functions"]:
        lines += ["Functions:"] + [_brief(f) for f in m["functions"]]
    if m["objects"]:
        lines += ["Objects:"] + [f"  {o['name']} - {o.get('summary', '')}" for o in m["objects"]]
    if m["enums"]:
        lines.append(f"Enums: {', '.join(e['name'] for e in m['enums'])}")
    return "\n".join(lines)


def _fmt_object(o: dict, verbosity: int):
    lines = [f"{o['name']}: {o.get('summary', '')}"]
    if o.get("extends"):
        lines.append(f"Extends: {o['extends']}")
    if o.get("constructors"):
        lines.append(f"Constructors: {', '.join(o['constructors'])}")
    if verbosity:
        lines.append(o.get("description", ""))
        if o.get("notes"):
            lines.append(f"Notes: {o['notes']}")
    lines += ["Methods:"] + [_brief(f) for f in o["methods"]]
    return "\n".join(lines)


def _fmt_enum(e: dict, verbosity: int):
    lines = [f"{e['name']} (enum): {e.get('summary', '')}"]
    if verbosity:
        lines.append(e.get("description", ""))
    lines += [f"  '{v['name']}' - {v.get('description', '')}" for v in e["values"]]
    return "\n".join(lines)


def lovr_docs(ctx: ex6.Context, query: str, verbosity: int = 0):
    """
    Look up LOVR (0.19) API docs. Returns signatures, descriptions, and method lists.
    query formats:
      lovr_docs("lovr")                     - list callbacks + top-level modules
      lovr_docs("lovr.graphics")            - list module functions, objects, enums
      lovr_docs("lovr.graphics.newBuffer")  - look up a module function
      lovr_docs("lovr.draw")                - look up a callback
      lovr_docs("Pass")                     - look up an object and list its methods
      lovr_docs("Pass:cube")                - look up a method on an object
      lovr_docs("DrawStyle")                - look up an enum
      lovr_docs("vector.angle")             - vector/quaternion are global modules (not under lovr.)
    verbosity: 0 = signatures only (default), 1 = full descriptions, args, notes, examples."""
    kind, item = _BY_KEY.get(query.strip(), (None, None))
    if not item:
        return f"'{query}' not found. Try lovr_docs(\"lovr\") to list modules and callbacks."
    fmt = {"fn": _fmt_fn, "module": _fmt_module, "object": _fmt_object, "enum": _fmt_enum}[kind]
    return fmt(item, verbosity)


if __name__ == "__main__":
    for q, v in [("lovr", 0), ("lovr.graphics", 0), ("lovr.draw", 0), ("lovr.graphics.newBuffer", 1),
                 ("Pass", 0), ("Pass:cube", 0), ("DrawStyle", 0), ("Mat4", 0), ("vector", 0), ("vector.angle", 0), ("nope", 0)]:
        print(f"=== {q} v{v} ===")
        print(lovr_docs(None, q, v)[:1200])
        print()
