#!/usr/bin/env python3
"""Convert a WebVTT/SRT subtitle file to clean plain text.

Removes WEBVTT headers, cue-timing lines, inline tags, and collapses the
rolling-duplicate lines that YouTube auto-captions produce. Prints one
space-joined line of text to stdout.
"""
import re
import sys

_SKIP_PREFIXES = ("WEBVTT", "Kind:", "Language:", "NOTE")


def clean(path):
    with open(path, encoding="utf-8") as f:
        raw = f.read().splitlines()

    texts = []
    for line in raw:
        line = line.strip()
        if not line:
            continue
        if line.startswith(_SKIP_PREFIXES):
            continue
        if "-->" in line:
            continue
        if re.fullmatch(r"\d+", line):  # SRT cue index
            continue
        text = re.sub(r"<[^>]+>", "", line)      # inline timing/style tags
        text = re.sub(r"\s+", " ", text).strip()
        if not text:
            continue
        if texts:
            last = texts[-1]
            if text == last:
                continue
            if text.startswith(last):  # rolling caption grew longer
                texts[-1] = text
                continue
        texts.append(text)

    return " ".join(texts)


def main():
    if len(sys.argv) != 2:
        print("Usage: clean_vtt.py <subtitle-file>", file=sys.stderr)
        sys.exit(1)
    print(clean(sys.argv[1]))


if __name__ == "__main__":
    main()
