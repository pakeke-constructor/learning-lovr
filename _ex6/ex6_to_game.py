"""
ex6 -> game bridge. The game (skullx11, src/modules/ex6_to_game.lua) connects over a local TCP socket to watch contexts and command them.
ex6 is the SSOT: the game only mirrors the state we push, and sends ops back.

Protocol: one packet per line, both ways: `MAGIC <json>\n`. A line without MAGIC drops the connection
(so stray local traffic, eg a browser POSTing to localhost, can never reach the `py` op).
A connection only gets state pushes after its first valid packet (the game sends `hello`).
  ex6 -> game: {"type": "state", "current": name, "order": [names], "contexts": {name: ctx}, "bodies": {hash: msg}}
      `order` = every context. `contexts` = only contexts that changed since the last push, each sent WHOLE (all its message hashes).
      Self-healing: every push, the next REFRESH_BUDGET slots (round-robin over every context + message) are re-encoded
      bypassing the caches, and their contexts are resent anyway. So any desync (in-place edits the cache missed,
      game code mutating its mirror) heals within one lap, at a fixed cost per push.
      `bodies` = only messages this connection doesn't have yet. Both sides keep exactly the bodies referenced by the latest state,
      so the caches stay bounded and in sync without any extra bookkeeping.
  game -> ex6: {"id": n, "op": "hello"|"prompt"|"fork"|"clear"|"new"|"yolo"|"stop"|"go"|"approve"|"py", ...args}
      -> {"type": "result", "id": n, "ok": bool, "value"|"error": str}
"""
import hashlib
import json
import socket
import threading
import time
import traceback

import ex6

PORT = 47306
MAGIC = "EX6G1"
CAP = 4000  # max chars per string we send (message text, tool args, streaming text)
PUSH_INTERVAL = 0.1
REFRESH_BUDGET = 10  # slots (1 per context + 1 per message) refreshed per push. Small on purpose: ex6's speed matters more than heal time

_clients = []  # connections that sent a valid packet; one shared snapshot is pushed to all of them
_ctx_cache = {}  # ctx name -> (msgs, ids, hashes, {hash: body}, {id(msg): entry}). Holds msgs so their ids can't be reused


def _cap(s, tail=False):
    s = str(s or "")
    if len(s) <= CAP:
        return s
    cut = f"...[{len(s) - CAP} chars cut]..."
    return cut + s[-CAP:] if tail else s[:CAP] + cut


def _first_arg(args):
    """-> first arg of a tool call, one line, short (the game shows `name(arg)`)."""
    v = next(iter(args.values()), "") if isinstance(args, dict) else args or ""
    return " ".join(str(v).split())[:200]


def _encode_msg(ctx, msg, old, force):
    """-> entry (msg, content, _snapshot, tool_calls, hash, body). Encoding + hashing only happens once per message (or when `force`):
    ex6 never edits text in place (str += makes a new object, purge_cache copies the Message), so `is` checks catch every change."""
    e = old.get(id(msg))
    if force or not (e and e[1] is msg.content and e[2] is msg._snapshot and e[3] is msg.tool_calls):
        text = ex6.tool_result_text(msg.get_msg(ctx))
        # the game shows what ex6's transcript shows: system prompts collapsed, tool results as a token count only
        if msg.role == "system":
            preview = msg.overview or next((l.strip() for l in text.split("\n") if l.strip()), "")
            body = {"role": "system", "chars": len(text), "lines": text.count("\n") + 1, "preview": preview[:50]}
        elif msg.role == "tool":
            body = {"role": "tool", "id": msg.tool_call_id, "tokens": ex6.get_token_estimate(text, ctx.model),
                    "error": text.startswith("ERROR:")}
        else:
            body = {"role": msg.role, "text": _cap(text),
                    "tool_calls": [{"id": tc["id"], "name": tc["name"], "arg": _first_arg(tc.get("args"))}
                                   for tc in msg.tool_calls or ()]}
        h = hashlib.sha1(json.dumps(body, sort_keys=True).encode()).hexdigest()[:16]
        e = (msg, msg.content, msg._snapshot, msg.tool_calls, h, body)
    return e


def _snapshot(tui, cursor):
    """-> (current, order, {name: ctx}, {hash: body}, {refreshed ctx names}, next cursor).
    Slots [cursor, cursor + REFRESH_BUDGET) are refreshed (re-encoded from scratch, their contexts resent)."""
    global _ctx_cache
    cache, contexts, bodies, refreshed = {}, {}, {}, set()
    end = cursor + REFRESH_BUDGET
    k = 0  # slot index: each context, then each of its messages
    for ctx in tui.context_list():
        msgs = ctx.get_messages()
        c = _ctx_cache.get(ctx.name)
        ids = tuple(map(id, msgs))
        if cursor < k + 1 + len(msgs) and k < end:
            refreshed.add(ctx.name)
        # fast path: same message objects as last push -> reuse everything (C-speed). What it misses, the refresh heals
        if ctx.name in refreshed or not c or c[1] != ids:
            old = c[4] if c else {}
            entries = {id(m): _encode_msg(ctx, m, old, cursor <= k + 1 + i < end) for i, m in enumerate(msgs)}
            c = (msgs, ids, [entries[i][4] for i in ids], {e[4]: e[5] for e in entries.values()}, entries)
        cache[ctx.name] = c
        bodies.update(c[3])
        k += 1 + len(msgs)
        pending = ctx.pending_message
        contexts[ctx.name] = {
            "name": ctx.name, "model": ctx.model, "parent": ctx.parent, "running": ctx.is_running(),
            "yolo": ctx.yolo, "waiting": bool(ctx.ui_stack),  # waiting = needs a human in ex6 (eg tool approval)
            "tokens": ctx.token_count(), "max_tokens": ctx.max_tokens, "tools": list(ctx.get_tools()),
            "msgs": c[2],
            # live stream of the current LLM turn (not a message yet), so the game can watch it work
            "cot": _cap(ctx.llm_cot, tail=True),
            "streaming": _cap(pending.content if pending and isinstance(pending.content, str) else "", tail=True),
        }
    _ctx_cache = cache  # sweep: contexts that are gone get dropped
    cursor = end if end < k else 0
    return tui.current.name if tui.current else None, list(contexts), contexts, bodies, refreshed, cursor


class _Client:
    def __init__(self, conn):
        self.conn = conn
        self.lock = threading.Lock()
        self.current, self.order = None, None
        self.ctxs = {}  # name -> the ctx dict last pushed
        self.sent = set()  # body hashes the game has = every hash in the last pushed state

    def send(self, obj):
        with self.lock:
            self.conn.sendall(f"{MAGIC} {json.dumps(obj)}\n".encode())

    def push(self, snap):
        current, order, contexts, bodies, refreshed, _ = snap
        changed = {n: c for n, c in contexts.items() if n in refreshed or self.ctxs.get(n) != c}
        if not changed and current == self.current and order == self.order:
            return
        new = {h: bodies[h] for c in changed.values() for h in c["msgs"] if h not in self.sent}
        self.send({"type": "state", "current": current, "order": order, "contexts": changed, "bodies": new})
        self.current, self.order, self.ctxs = current, order, contexts
        self.sent = set(bodies)


def _push_loop(app):
    cursor = 0
    while True:
        time.sleep(PUSH_INTERVAL)
        if not _clients:
            continue  # no game connected: costs nothing
        try:
            snap = _snapshot(app.tui, cursor)
            cursor = snap[-1]
        except Exception:  # never raise: a thread crash is fatal to ex6. (eg contexts changing mid-snapshot)
            app.debug_print("[ex6_to_game] snapshot failed:", traceback.format_exc())
            continue
        for client in list(_clients):
            try:
                client.push(snap)
            except Exception:  # client gone; its reader thread cleans up
                client.conn.close()


def _serve_client(app, conn):
    client = _Client(conn)
    try:
        for line in conn.makefile("r", encoding="utf-8"):
            magic, _, payload = line.partition(" ")
            if magic != MAGIC:
                break
            if client not in _clients:
                _clients.append(client)
            req = json.loads(payload)
            try:
                value = OPS[req["op"]](app, app.tui, req)
                reply = {"type": "result", "id": req.get("id"), "ok": True, "value": None if value is None else str(value)}
            except Exception:
                reply = {"type": "result", "id": req.get("id"), "ok": False, "error": _cap(traceback.format_exc())}
            client.send(reply)
    except Exception as e:  # bad json / socket gone: drop the client, never crash ex6
        app.debug_print("[ex6_to_game] client dropped:", repr(e))
    finally:
        if client in _clients:
            _clients.remove(client)
        conn.close()


def _get_ctx(tui, name):
    ctx = tui.get_context(name) if name else tui.current
    if not ctx:
        raise ValueError(f"no context {name!r}")
    return ctx


def _unique_name(tui, base):
    n = 2
    while tui.get_context(f"{base}.{n}"): n += 1
    return f"{base}.{n}"


def _op_prompt(app, tui, req):
    _get_ctx(tui, req.get("ctx")).submit_input(ex6.InputValue(req["text"]))


def _op_fork(app, tui, req):
    ctx = _get_ctx(tui, req.get("ctx"))
    return tui.add_context(ctx.fork(_unique_name(tui, ctx.name))).name


def _op_clear(app, tui, req):
    _get_ctx(tui, req.get("ctx")).clear()


def _op_new(app, tui, req):
    base = tui.favorite or tui.current
    ctx = base.fork(_unique_name(tui, base.name))
    ctx.clear()
    if "yolo" in req: ctx.yolo = bool(req["yolo"])  # else inherited from base
    return tui.add_context(ctx).name


def _op_yolo(app, tui, req):
    ctx = _get_ctx(tui, req.get("ctx"))
    ctx.yolo = not ctx.yolo


def _op_stop(app, tui, req):
    ctx = _get_ctx(tui, req.get("ctx"))
    if ctx.is_running(): ctx.stop_early = True


def _op_go(app, tui, req):
    """Run the agent without a new message (ex6's `g`)."""
    ctx = _get_ctx(tui, req.get("ctx"))
    if ctx.is_running(): raise ValueError("running (s to stop)")
    ctx.invoke()


def _op_approve(app, tui, req):
    """Activate the pending request (eg tool approval), like enter in ex6."""
    ctx = _get_ctx(tui, req.get("ctx"))
    request = ctx.ui_stack[-1] if ctx.ui_stack else None
    if not (request and request.pending()): raise ValueError("nothing to approve")
    request.panel.action("activate", request)


def _op_py(app, tui, req):
    """Trusted python. Gets `app`, `tui`, `ex6`; whatever it puts in `result` is sent back."""
    scope = {"app": app, "tui": tui, "ex6": ex6, "result": None}
    exec(req["code"], scope)
    return scope["result"]


OPS = {"hello": lambda app, tui, req: None, "prompt": _op_prompt, "fork": _op_fork, "clear": _op_clear, "new": _op_new,
       "yolo": _op_yolo, "stop": _op_stop, "go": _op_go, "approve": _op_approve, "py": _op_py}


def _serve(app):
    srv = socket.socket()
    try:
        srv.bind(("127.0.0.1", PORT))
    except OSError as e:  # another ex6 has it: first ex6 wins
        return app.debug_print(f"[ex6_to_game] port {PORT} taken, bridge off:", repr(e))
    srv.listen()
    threading.Thread(target=_push_loop, args=(app,), daemon=True).start()
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=_serve_client, args=(app, conn), daemon=True).start()


def setup(app: ex6.App):
    threading.Thread(target=_serve, args=(app,), daemon=True).start()
