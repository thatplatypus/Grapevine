#!/usr/bin/env python3
"""Token-count the Grapevine sample app against its ASP.NET twin.

Uses the legacy Claude tokenizer that shipped inside older Anthropic Python SDKs
(`pip install "anthropic==0.38.0" tokenizers`). Current Claude models use a newer
vocabulary, so treat the absolute numbers as indicative; the ratio is the point.

    python3 comparison/tokens.py
"""
import os
import re
import sys
from pathlib import Path

try:
    import anthropic
    import tokenizers
except ImportError:
    sys.exit('needs: pip install "anthropic==0.38.0" tokenizers')

ROOT = Path(__file__).resolve().parent.parent
tok = tokenizers.Tokenizer.from_file(os.path.join(os.path.dirname(anthropic.__file__), "tokenizer.json"))


def strip_emojicode(src: str) -> str:
    src = re.sub(r"📗.*?📗", "", src, flags=re.S)  # doc comments
    src = re.sub(r"📘.*?📘", "", src, flags=re.S)  # package docs
    src = re.sub(r"💭[^\n]*", "", src)  # line comments
    return "\n".join(l for l in src.splitlines() if l.strip())


def strip_csharp(src: str) -> str:
    src = re.sub(r"//[^\n]*", "", src)
    return "\n".join(l for l in src.splitlines() if l.strip())


def count(paths, strip):
    raw = "\n".join(p.read_text() for p in paths)
    code = strip(raw)
    return {
        "lines": len(code.splitlines()),
        "bytes": len(code.encode()),
        "tokens": len(tok.encode(code).ids),
        "tokens_with_comments": len(tok.encode(raw).ids),
    }


emoji_app = count([ROOT / "samples" / "todo" / f for f in ("main.🍇", "startup.🍇", "todos.🍇")], strip_emojicode)
csharp_app = count([ROOT / "comparison/aspnet/Program.cs"], strip_csharp)
framework = count(sorted((ROOT / "packages/grapevine").glob("*.🍇")), strip_emojicode)

rows = [("Grapevine app (Emojicode)", emoji_app), ("ASP.NET minimal API (C#)", csharp_app)]
print(f"{'':28}{'lines':>7}{'bytes':>8}{'tokens':>8}{'w/ comments':>13}")
for name, c in rows:
    print(f"{name:28}{c['lines']:>7}{c['bytes']:>8}{c['tokens']:>8}{c['tokens_with_comments']:>13}")
print(f"\nEmojicode / C# tokens: {emoji_app['tokens'] / csharp_app['tokens']:.2f}x")
print(f"Emojicode / C# lines:  {emoji_app['lines'] / csharp_app['lines']:.2f}x")
print(f"\nGrapevine framework itself: {framework['lines']} lines, {framework['tokens']} tokens "
      "(ASP.NET ships this in the box)")

# Per-token cost of the syntax, for the curious.
samples = ["🍇", "🍉", "❗️", "➡️", "↩️", "↪️", "🔤", "🧲", "{", "}", "return", "if", "=>", "\"", "var"]
print("\nTokens per construct: " + "  ".join(f"{s} {len(tok.encode(s).ids)}" for s in samples))
