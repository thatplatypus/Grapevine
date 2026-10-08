#!/usr/bin/env python3
"""Token-count the Grapevine Todo sample against its ASP.NET twin.

Uses the legacy Claude tokenizer that shipped inside older Anthropic Python SDKs
(`pip install "anthropic==0.38.0" tokenizers`). Current Claude models use a newer
vocabulary, so treat the absolute numbers as indicative; the ratio is the point.

    python3 comparison/tokens.py

What is counted is each program's own source: what a person writes to have the sample,
on a framework that is already there. Comments are taken out of both by the same rule,
and so are empty lines. Not counted on either side: tests, the page (both serve the same
files), build scripts and project files, and the frameworks themselves.
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

SAMPLE = [ROOT / "samples" / "todo" / name for name in ("main.🍇", "startup.🍇", "todos.🍇")]
TWIN = [ROOT / "comparison" / "aspnet" / "Program.cs"]
FRAMEWORK = sorted((ROOT / "packages" / "grapevine").glob("*.🍇"))


def without_blank_lines(src: str) -> str:
    return "\n".join(line for line in src.splitlines() if line.strip())


def strip_emojicode(src: str) -> str:
    src = re.sub(r"📗.*?📗", "", src, flags=re.S)  # doc comments
    src = re.sub(r"📘.*?📘", "", src, flags=re.S)  # package docs
    # A line comment, but not a 💭 that stands inside a text.
    src = re.sub(r"(🔤.*?🔤)|💭[^\n]*", lambda found: found.group(1) or "", src)
    return without_blank_lines(src)


def strip_csharp(src: str) -> str:
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    # A line comment, but not the // of an address that stands inside a text.
    src = re.sub(r'("(?:\\.|[^"\\\n])*")|//[^\n]*', lambda found: found.group(1) or "", src)
    return without_blank_lines(src)


def count(paths, strip):
    raw = "\n".join(path.read_text() for path in paths)
    code = strip(raw)
    return {
        "lines": len(code.splitlines()),
        "bytes": len(code.encode()),
        "tokens": len(tok.encode(code).ids),
        "tokens_with_comments": len(tok.encode(raw).ids),
    }


def row(name, counted):
    return (f"{name:34}{counted['lines']:>7}{counted['bytes']:>9}{counted['tokens']:>8}"
            f"{counted['tokens_with_comments']:>13}")


sample = count(SAMPLE, strip_emojicode)
twin = count(TWIN, strip_csharp)
framework = count(FRAMEWORK, strip_emojicode)

print(f"{'':34}{'lines':>7}{'bytes':>9}{'tokens':>8}{'w/ comments':>13}")
print(row("Grapevine sample (Emojicode)", sample))
for path in SAMPLE:
    print(row("  " + str(path.relative_to(ROOT)), count([path], strip_emojicode)))
print(row("ASP.NET minimal API (C#)", twin))
for path in TWIN:
    print(row("  " + str(path.relative_to(ROOT)), count([path], strip_csharp)))
print(f"\nEmojicode / C# tokens: {sample['tokens'] / twin['tokens']:.2f}x")
print(f"Emojicode / C# lines:  {sample['lines'] / twin['lines']:.2f}x")
print(f"Emojicode / C# bytes:  {sample['bytes'] / twin['bytes']:.2f}x")
print(f"\nGrapevine framework itself: {len(FRAMEWORK)} files, {framework['lines']} lines, "
      f"{framework['tokens']} tokens (ASP.NET ships this in the box)")

# Per-token cost of the syntax, for the curious.
samples = ["🍇", "🍉", "❗️", "➡️", "↩️", "↪️", "🔤", "🧲", "{", "}", "return", "if", "=>", "\"", "var"]
print("\nTokens per construct: " + "  ".join(f"{s} {len(tok.encode(s).ids)}" for s in samples))


def tokens(text):
    return len(tok.encode(text).ids)


# Where the tokens go: the numbers that the README's prose gives. A mark is counted at what
# it costs by itself, times how often it stands in the code.
sample_code = strip_emojicode("\n".join(path.read_text() for path in SAMPLE))
twin_code = strip_csharp("\n".join(path.read_text() for path in TWIN))
MARKS = ["🍇", "🍉", "❗️", "➡️", "↩️", "↪️", "🔤"]
COUNTERPARTS = ["{", "}", "(", ")", ";", "=>", '"']
marks = sum(sample_code.count(mark) * tokens(mark) for mark in MARKS)
counterparts = sum(twin_code.count(mark) * tokens(mark) for mark in COUNTERPARTS)
counterparts += len(re.findall(r"\breturn\b", twin_code)) * tokens("return")
calls = sample_code.count("❗️")
quotes = sample_code.count("🔤")
in_emoji = sum(tokens(run) for run in re.findall(r"[^\x00-\x7f]+", sample_code))
said_sample = sum(tokens(text) for text in re.findall(r"🔤(.*?)🔤", sample_code, flags=re.S) if text)
said_twin = sum(tokens(text) for text in re.findall(r'"((?:\\.|[^"\\\n])*)"', twin_code) if text)

print("\nWhere the tokens go")
print(f"  the marks {' '.join(MARKS)} in the sample: {marks} tokens, "
      f"{100 * marks / sample['tokens']:.0f} in every 100")
print(f"  their counterparts {' '.join(COUNTERPARTS)} return in the twin: {counterparts} tokens")
print(f"  calls, which each end in ❗️: {calls}, {calls * tokens('❗️')} tokens")
print(f"  🔤 at the ends of texts: {quotes}, {quotes * tokens('🔤')} tokens")
print(f"  in runs of emoji: {in_emoji} of the sample's {sample['tokens']} tokens, "
      f"{10 * in_emoji / sample['tokens']:.1f} in every 10")
print(f"  what is said between quotes: {said_sample} tokens in the sample, {said_twin} in the twin")
