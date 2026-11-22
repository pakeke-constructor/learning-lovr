'''
LOVR API documentation lookup tool for coding agents.

Data: lovr_docs.json, generated from lovr-docs v0.19.0 api/init.lua via lua_to_json.lua.

Run directly for a smoke test (needs ex6 on PYTHONPATH).
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


def _norm(q: str):
    q = q.strip().strip("`").removesuffix("()").replace(":", ".").lower()
    return q.removeprefix("lovr.") if q != "lovr" else q


_ALL = list(_BY_KEY.items())
_BY_NORM: dict[str, list[str]] = {}
_BY_NAME: dict[str, list[str]] = {}  # bare name: "newBuffer", "cube"
for _k in _BY_KEY:
    _BY_NORM.setdefault(_norm(_k), []).append(_k)
    _BY_NAME.setdefault(_norm(_k).rsplit(".", 1)[-1], []).append(_k)


def _summary(key: str):
    return f"  {key} - {_BY_KEY[key][1].get('summary', '')}"


def _search(term: str, limit: int = 15):
    words = _norm(term).replace(".", " ").split()
    hits = []
    for key, (_, item) in _ALL:
        name, summary = key.lower(), item.get("summary", "").lower()
        text = f"{name} {summary} {item.get('description', '').lower()}"
        if all(w in text for w in words):
            hits.append((-3 * sum(w in name for w in words) - sum(w in summary for w in words), len(key), key))
    keys = [k for *_, k in sorted(hits)]
    if not keys:
        import difflib
        close = difflib.get_close_matches(_norm(term), list(_BY_NORM) + list(_BY_NAME), n=limit, cutoff=0.6)
        keys = list(dict.fromkeys(k for c in close for k in _BY_NORM.get(c, []) + _BY_NAME.get(c, [])))
    more = f"\n  ...{len(keys) - limit} more, refine search" if len(keys) > limit else ""
    return "\n".join(_summary(k) for k in keys[:limit]) + more


def _lookup(term: str, verbosity: int):
    keys = [term] if term in _BY_KEY else _BY_NORM.get(_norm(term)) or _BY_NAME.get(_norm(term), [])
    if len(keys) == 1:
        kind, item = _BY_KEY[keys[0]]
        return {"fn": _fmt_fn, "module": _fmt_module, "object": _fmt_object, "enum": _fmt_enum}[kind](item, verbosity)
    if keys:
        return f"'{term}' is ambiguous:\n" + "\n".join(_summary(k) for k in keys)
    found = _search(term)
    return f"No exact match for '{term}'. " + (f"Search results:\n{found}" if found else 'Nothing found. Try lovr_docs("lovr").')


def lovr_docs(ctx: ex6.Context, query: str, verbosity: int = 0):
    """
    Look up the LOVR 0.19 API docs.

    Examples:
      lovr_docs("lovr")                    # list all callbacks and modules (start here)
      lovr_docs("lovr.graphics")           # list a module's functions, objects, enums
      lovr_docs("lovr.graphics.newBuffer") # function signatures
      lovr_docs("Pass")                    # list an object's methods
      lovr_docs("Pass:cube")               # method signatures
      lovr_docs("DrawStyle")               # enum values
      lovr_docs("Pass:cube, Pass:sphere")  # several lookups in one call, comma-separated

    You don't need exact names. These all find the same thing:
      "lovr.graphics.newBuffer", "graphics.newBuffer", "newBuffer", "newbuffer"
    Same for methods: "Pass:cube" and "pass.cube" both work.

    If nothing matches exactly, the query is used as a keyword search, e.g. "texture filter".

    verbosity=0 gives a one-line summary and the signatures. Use verbosity=1 for full descriptions, argument docs, notes and examples."""
    terms = [t for t in query.split(",") if t.strip()]
    if not terms:
        return lovr_docs(ctx, "lovr", verbosity)
    out = [_lookup(t.strip(), verbosity) for t in terms]
    return out[0] if len(out) == 1 else "\n\n".join(f"=== {t.strip()} ===\n{o}" for t, o in zip(terms, out))


if __name__ == "__main__":
    for q, v in [("lovr", 0), ("graphics", 0), ("Pass:draw", 0), ("TEXTURE", 0), ("draw", 0), ("newBuffer", 1), ("pass.cube", 0), ("Pass:cube, Mat4:lookAt, DrawStyle", 0),
                 ("getWidth", 0), ("texture filter", 0), ("newBufer", 0), ("vector.angle", 0), ("xyzzy", 0)]:
        print(f"##### {q} v{v}")
        print(lovr_docs(None, q, v)[:1500])
        print()
