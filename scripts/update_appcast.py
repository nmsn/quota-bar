#!/usr/bin/env python3
"""Update Sparkle appcast.xml: insert a new item or replace an enclosure version."""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
from datetime import datetime, timezone, timedelta


VERSION_RE = re.compile(r'sparkle:version="([^"]+)"')
INTEGER_RE = re.compile(r"^[0-9]+$")
ENCLOSURE_RE = re.compile(r"<enclosure\b[^>]*>", re.DOTALL)
ITEM_RE = re.compile(r"<item\b[^>]*>.*?</item>", re.DOTALL)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Update Sparkle appcast.xml")
    p.add_argument("--marketing", required=True, help="Marketing version (shortVersionString)")
    p.add_argument("--build", required=True, help="Build number (sparkle:version)")
    p.add_argument("--dmg", required=True, help="Path to DMG for length")
    p.add_argument("--appcast", required=True, help="Path to appcast.xml")
    p.add_argument("--url", default=None, help="Enclosure URL (default from marketing)")
    p.add_argument("--date", default=None, help="pubDate (RFC 2822)")
    p.add_argument("--title", default=None, help="Item title")
    p.add_argument(
        "--replace-enclosure-version",
        default=None,
        metavar="OLD",
        help="Replace existing enclosure with sparkle:version=OLD",
    )
    return p.parse_args(argv)


def default_url(marketing: str) -> str:
    return (
        f"https://github.com/nmsn/quota-bar/releases/download/v{marketing}/"
        f"QuotaBar-{marketing}.dmg"
    )


def default_date() -> str:
    # Asia/Shanghai (+0800) without requiring zoneinfo
    tz = timezone(timedelta(hours=8))
    return datetime.now(tz).strftime("%a, %d %b %Y %H:%M:%S +0800")


def collect_versions(text: str) -> list[str]:
    return VERSION_RE.findall(text)


def build_item_xml(
    *,
    marketing: str,
    build: str,
    length: int,
    url: str,
    date: str,
    title: str,
) -> str:
    return (
        f"    <item>\n"
        f"      <title>{title}</title>\n"
        f"      <pubDate>{date}</pubDate>\n"
        f'      <enclosure url="{url}" sparkle:version="{build}" '
        f'sparkle:shortVersionString="{marketing}" length="{length}" '
        f'type="application/octet-stream"/>\n'
        f"    </item>\n"
    )


def insert_item(text: str, item_xml: str) -> str:
    m = re.search(r"<item\b", text)
    if m is None:
        # No existing items: insert before </channel>
        close = text.find("</channel>")
        if close == -1:
            print("error: no </channel> in appcast", file=sys.stderr)
            sys.exit(1)
        return text[:close] + item_xml + text[close:]
    return text[: m.start()] + item_xml + text[m.start() :]


def find_replace_enclosure(
    text: str, old_version: str, marketing: str
) -> re.Match[str] | None:
    """Find enclosure with sparkle:version=OLD preferring marketing match."""
    candidates: list[tuple[re.Match[str], bool]] = []
    for enc in ENCLOSURE_RE.finditer(text):
        enc_text = enc.group(0)
        if f'sparkle:version="{old_version}"' not in enc_text:
            continue
        # Prefer URL containing marketing or surrounding item title containing marketing
        url_match = marketing in enc_text
        # Find enclosing item
        item_match = False
        for item in ITEM_RE.finditer(text):
            if item.start() <= enc.start() < item.end():
                if marketing in item.group(0):
                    item_match = True
                break
        preferred = url_match or item_match
        candidates.append((enc, preferred))

    if not candidates:
        return None
    preferred = [c for c in candidates if c[1]]
    if preferred:
        return preferred[0][0]
    return candidates[0][0]


def update_enclosure_attrs(
    enclosure: str,
    *,
    build: str,
    marketing: str,
    length: int,
    url: str | None,
) -> str:
    # sparkle:version
    enclosure = re.sub(
        r'sparkle:version="[^"]*"',
        f'sparkle:version="{build}"',
        enclosure,
        count=1,
    )
    # shortVersionString: set or add
    if "sparkle:shortVersionString=" in enclosure:
        enclosure = re.sub(
            r'sparkle:shortVersionString="[^"]*"',
            f'sparkle:shortVersionString="{marketing}"',
            enclosure,
            count=1,
        )
    else:
        enclosure = re.sub(
            r'(sparkle:version="[^"]*")',
            rf'\1 sparkle:shortVersionString="{marketing}"',
            enclosure,
            count=1,
        )
    # length
    if re.search(r'\blength="[^"]*"', enclosure):
        enclosure = re.sub(
            r'\blength="[^"]*"',
            f'length="{length}"',
            enclosure,
            count=1,
        )
    else:
        enclosure = re.sub(
            r"(/>)$",
            f' length="{length}"\\1',
            enclosure,
            count=1,
        )
    # url if provided
    if url is not None:
        enclosure = re.sub(
            r'\burl="[^"]*"',
            f'url="{url}"',
            enclosure,
            count=1,
        )
    return enclosure


def atomic_write(path: str, content: str) -> None:
    directory = os.path.dirname(os.path.abspath(path)) or "."
    fd, tmp_path = tempfile.mkstemp(dir=directory, prefix=".appcast-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(tmp_path, path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if not INTEGER_RE.match(args.build):
        print(f"error: --build must be a positive integer, got {args.build!r}", file=sys.stderr)
        return 1
    build = args.build
    build_int = int(build)
    if build_int < 1:
        print("error: --build must be a positive integer", file=sys.stderr)
        return 1

    dmg = args.dmg
    if not os.path.isfile(dmg):
        print(f"error: DMG not found: {dmg}", file=sys.stderr)
        return 1
    length = os.path.getsize(dmg)
    if length <= 0:
        print(f"error: DMG is empty: {dmg}", file=sys.stderr)
        return 1

    appcast_path = args.appcast
    if not os.path.isfile(appcast_path):
        print(f"error: appcast not found: {appcast_path}", file=sys.stderr)
        return 1

    text = open(appcast_path, encoding="utf-8").read()
    marketing = args.marketing
    url = args.url if args.url is not None else default_url(marketing)
    date = args.date if args.date is not None else default_date()
    title = args.title if args.title is not None else f"Version {marketing}"

    final_url = url

    if args.replace_enclosure_version is not None:
        old = args.replace_enclosure_version
        match = find_replace_enclosure(text, old, marketing)
        if match is None:
            print(
                f"error: no enclosure with sparkle:version={old!r} matching marketing",
                file=sys.stderr,
            )
            return 1
        new_enc = update_enclosure_attrs(
            match.group(0),
            build=build,
            marketing=marketing,
            length=length,
            url=args.url,  # only update url if explicitly provided
        )
        text = text[: match.start()] + new_enc + text[match.end() :]
        # Extract url from resulting enclosure for summary
        um = re.search(r'\burl="([^"]*)"', new_enc)
        if um:
            final_url = um.group(1)
    else:
        versions = collect_versions(text)
        if any(v == build for v in versions):
            print(f"error: sparkle:version={build!r} already exists", file=sys.stderr)
            return 1
        int_versions = [int(v) for v in versions if INTEGER_RE.match(v)]
        if any(v >= build_int for v in int_versions):
            print(
                f"error: --build {build} is not greater than existing max "
                f"{max(int_versions)}",
                file=sys.stderr,
            )
            return 1
        if any("." in v for v in versions):
            print(
                "warning: appcast contains dotted sparkle:version values "
                "(legacy marketing-style); not rewritten",
                file=sys.stderr,
            )
        item_xml = build_item_xml(
            marketing=marketing,
            build=build,
            length=length,
            url=url,
            date=date,
            title=title,
        )
        text = insert_item(text, item_xml)
        final_url = url

    atomic_write(appcast_path, text)
    print(f"marketing={marketing} build={build} length={length} url={final_url}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
