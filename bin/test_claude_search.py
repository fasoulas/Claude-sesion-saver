#!/usr/bin/env python3
"""Self-check for claude-search's pure logic. Run: python3 bin/test_claude_search.py"""

import importlib.util
import os
import re
from importlib.machinery import SourceFileLoader

path = os.path.join(os.path.dirname(__file__), "claude-search")
loader = SourceFileLoader("claude_search", path)
spec = importlib.util.spec_from_loader(loader.name, loader)
cs = importlib.util.module_from_spec(spec)
loader.exec_module(cs)

assert cs.extract_text("plain string") == "plain string"
assert (
    cs.extract_text(
        [{"type": "text", "text": "hello"}, {"type": "tool_result", "content": "x"}]
    )
    == "hello"
)
assert cs.extract_text([{"type": "tool_result", "content": "x"}]) == ""
assert cs.extract_text(None) == ""

pattern = re.compile("needle", re.IGNORECASE)
text = "x" * 100 + "NEEDLE" + "y" * 100
snippet = cs.make_snippet(text, pattern, width=20)
assert "NEEDLE" in snippet
assert snippet.startswith("…") and snippet.endswith("…")

print("ok")
