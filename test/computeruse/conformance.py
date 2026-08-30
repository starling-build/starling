#!/usr/bin/env python3
"""Drive Starling's computer use with the REAL toolset, against the real API.

The MCP server (build/computer-use-mcp.py) is our approximation of
`computer_toolset_20260801`: the same seventeen member names, the same
semantics, one tool call at a time over stdio. An approximation drifts. This
runs the ACTUAL toolset against the ACTUAL model, executing every member
through the same executor the MCP server uses, so the two cannot disagree
without this failing.

It is a manual tier. It needs API credentials and a running Starling desktop,
it costs money, and it is NOT in test/run.sh — nothing that spends tokens
belongs in a suite people run on every change.

    pip install anthropic          # not a dependency of anything else here
    export ANTHROPIC_API_KEY=...   # or `ant auth login`
    build/run-desktop.sh &         # a live shell, so the broker exists
    test/computeruse/conformance.py --app settings

    test/computeruse/conformance.py --dry-run   # no API, no desktop: prints
                                                # the request we would send

**The window binding is the interesting part.** The toolset has no notion of a
window — it assumes one screen and takes bare coordinates, which is what a VM
gives it. Starling has no such thing on offer: an agent sees exactly the
windows it owns. So this loop opens one window up front and binds every action
to it. The model addresses a screen; the compositor delivers to one window;
the human's desktop is not in the picture. That the contract is satisfiable at
all under per-window scope is the thing being tested.
"""

import argparse
import base64
import importlib.util
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# The one executor, shared with the MCP server. If this import breaks, the
# conformance loop is testing something other than what ships.
_spec = importlib.util.spec_from_file_location(
    "starling_computer_use", os.path.join(REPO, "build", "computer-use-mcp.py"))
cu = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cu)


# The toolset as declared on the wire. One entry — the seventeen members are
# inside it, and the model dispatches by member name.
TOOLSET = {"type": "computer_toolset_20260801", "name": "computer"}

MODEL = "claude-opus-5"

SYSTEM = """\
You are driving a real desktop through the computer toolset. One application \
window fills the screen; there is nothing else to switch to, and no desktop, \
dock or menu bar outside it.

Take a screenshot before your first action and after anything that should have \
changed something. Work from what the screenshot shows, not from what you \
expect an application of this kind to look like. When the task is done, say so \
in one sentence and stop.\
"""

DEFAULT_TASK = (
    "This is the Starling desktop's Settings app. Open its Network pane, then "
    "tell me the name of the first row of settings shown in that pane."
)


def blocks_to_tool_uses(message):
    """The tool_use blocks of one assistant message, in order.

    Toolset members arrive as ordinary tool_use blocks whose `name` is the
    member (`screenshot`, `left_click`, …) and whose `toolset_name` is the
    toolset they came from. Reading `name` alone would collide the day a
    second toolset is declared, so check both.
    """
    out = []
    for b in message.content:
        if b.type != "tool_use":
            continue
        toolset = getattr(b, "toolset_name", None)
        if toolset not in (None, TOOLSET["name"]):
            raise SystemExit("unexpected toolset %r on tool_use %s" % (toolset, b.id))
        out.append(b)
    return out


def run_turn(ex, win, tool_uses, verbose):
    """Execute one assistant turn's tool calls and build the tool_result blocks.

    Batch semantics come from the executor, which is the point: sequential,
    stop at the first failure, everything after it answered with the contract's
    exact "Not executed" text rather than silently dropped.
    """
    actions = []
    for b in tool_uses:
        args = dict(b.input or {})
        # `wait` is the one member with no window — it pauses the agent, not a
        # window. Everything else is bound to the window this loop opened.
        if b.name != "wait":
            args["win"] = win
        actions.append({"name": b.name, "input": args})

    results = ex.run_batch(actions)

    blocks = []
    for b, r in zip(tool_uses, results):
        content = []
        if r.get("text"):
            content.append({"type": "text", "text": r["text"]})
        if r.get("image"):
            content.append({"type": "image", "source": {
                "type": "base64", "media_type": "image/png",
                "data": base64.b64encode(r["image"]).decode()}})
        block = {"type": "tool_result", "tool_use_id": b.id,
                 "content": content or [{"type": "text", "text": "ok"}]}
        if r.get("is_error"):
            block["is_error"] = True
        blocks.append(block)
        if verbose:
            mark = "ERR " if r.get("is_error") else "ok  "
            print("  %s%-16s %s" % (mark, b.name, r.get("text", "")[:100]),
                  file=sys.stderr)
    return blocks


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--app", default="settings",
                    help="app id to open and drive (default: settings)")
    ap.add_argument("--task", default=DEFAULT_TASK)
    ap.add_argument("--max-turns", type=int, default=20)
    ap.add_argument("--effort", default="high",
                    choices=["low", "medium", "high", "xhigh", "max"])
    ap.add_argument("--dry-run", action="store_true",
                    help="print the request we would send and exit; no API "
                         "call, no desktop needed")
    ap.add_argument("-q", "--quiet", action="store_true")
    args = ap.parse_args(argv)

    if args.dry_run:
        import json
        print(json.dumps({
            "model": MODEL,
            "max_tokens": 64000,
            "system": SYSTEM,
            "tools": [TOOLSET],
            "thinking": {"type": "adaptive"},
            "output_config": {"effort": args.effort},
            "messages": [{"role": "user", "content": args.task}],
        }, indent=2))
        return 0

    try:
        import anthropic
    except ImportError:
        raise SystemExit("pip install anthropic — this tier is not stdlib-only")

    ex = cu.Executor(name="computer-use conformance")
    launched = ex.computer_launch(app=args.app)
    win = launched["text"].rsplit(" ", 1)[-1]
    if not args.quiet:
        print("driving %s in %s" % (args.app, win), file=sys.stderr)
    ex.computer_settled(win=win)

    client = anthropic.Anthropic()
    messages = [{"role": "user", "content": args.task}]

    for turn in range(args.max_turns):
        # Streaming, because a computer-use turn is long by nature: the model
        # thinks, looks at a screenshot, and acts, and a non-streaming request
        # at this max_tokens invites an HTTP timeout rather than an answer.
        with client.messages.stream(
            model=MODEL,
            max_tokens=64000,
            system=SYSTEM,
            tools=[TOOLSET],
            thinking={"type": "adaptive"},
            output_config={"effort": args.effort},
            messages=messages,
        ) as stream:
            message = stream.get_final_message()

        # Refusals are a content outcome, not an exception — read stop_reason
        # before touching content, or a refused turn crashes on content[0].
        if message.stop_reason == "refusal":
            detail = getattr(message, "stop_details", None)
            raise SystemExit("model refused: %s" % (
                getattr(detail, "category", None) or "no category given"))

        for b in message.content:
            if b.type == "text" and b.text.strip() and not args.quiet:
                print("· " + b.text.strip(), file=sys.stderr)

        messages.append({"role": "assistant", "content": message.content})
        tool_uses = blocks_to_tool_uses(message)
        if not tool_uses:
            if not args.quiet:
                print("done in %d turn(s)" % (turn + 1), file=sys.stderr)
            return 0
        messages.append({"role": "user",
                         "content": run_turn(ex, win, tool_uses, not args.quiet)})

    raise SystemExit("gave up after %d turns" % args.max_turns)


if __name__ == "__main__":
    sys.exit(main())
