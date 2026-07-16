#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/update-appcast.sh"
FIX="$ROOT/scripts/tests/fixtures/appcast-sample.xml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# tiny fake dmg
dd if=/dev/zero of="$TMP/fake.dmg" bs=1024 count=2 2>/dev/null
SIZE=$(stat -f %z "$TMP/fake.dmg")

# --- insert succeeds ---
cp "$FIX" "$TMP/a.xml"
"$SCRIPT" --marketing 2.0.4 --build 5 --dmg "$TMP/fake.dmg" --appcast "$TMP/a.xml" \
  --date "Thu, 16 Jul 2026 10:58:00 +0800" || fail "insert should succeed"
grep -q 'sparkle:version="5"' "$TMP/a.xml" || fail "missing version 5"
grep -q 'sparkle:shortVersionString="2.0.4"' "$TMP/a.xml" || fail "missing shortVersionString"
grep -q "length=\"$SIZE\"" "$TMP/a.xml" || fail "bad length"
# new item must appear before 2.0.3
python3 - <<'PY' "$TMP/a.xml" || fail "order"
import sys
t=open(sys.argv[1]).read()
i5=t.find('sparkle:version="5"')
i3=t.find('sparkle:version="2.0.3"')
assert i5!=-1 and i3!=-1 and i5<i3
PY
pass "insert"

# --- duplicate build fails ---
cp "$TMP/a.xml" "$TMP/b.xml"
if "$SCRIPT" --marketing 2.0.5 --build 5 --dmg "$TMP/fake.dmg" --appcast "$TMP/b.xml"; then
  fail "duplicate build should fail"
fi
pass "duplicate build"

# --- build not greater than existing integer max (after we have integer 5) ---
if "$SCRIPT" --marketing 2.0.5 --build 4 --dmg "$TMP/fake.dmg" --appcast "$TMP/b.xml"; then
  fail "build 4 <= 5 should fail"
fi
pass "monotonic"

# --- missing dmg fails ---
cp "$FIX" "$TMP/c.xml"
if "$SCRIPT" --marketing 2.0.4 --build 5 --dmg "$TMP/nope.dmg" --appcast "$TMP/c.xml"; then
  fail "missing dmg should fail"
fi
pass "missing dmg"

# --- replace enclosure version ---
cat > "$TMP/d.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>QuotaBar Updates</title>
    <link>https://nmsn.github.io/quota-bar/appcast.xml</link>
    <item>
      <title>Version 2.0.4</title>
      <pubDate>Thu, 16 Jul 2026 10:58:00 +0800</pubDate>
      <enclosure url="https://github.com/nmsn/quota-bar/releases/download/v2.0.4/QuotaBar-2.0.4.dmg" sparkle:version="2.0.4" length="1" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF
"$SCRIPT" --marketing 2.0.4 --build 5 --dmg "$TMP/fake.dmg" --appcast "$TMP/d.xml" \
  --replace-enclosure-version 2.0.4 || fail "replace should succeed"
grep -q 'sparkle:version="5"' "$TMP/d.xml" || fail "replace version"
grep -q 'sparkle:shortVersionString="2.0.4"' "$TMP/d.xml" || fail "replace short"
grep -q "length=\"$SIZE\"" "$TMP/d.xml" || fail "replace length"
if grep -q 'sparkle:version="2.0.4"' "$TMP/d.xml"; then fail "old version should be gone"; fi
pass "replace"

# --- replace missing OLD fails ---
cp "$FIX" "$TMP/e.xml"
if "$SCRIPT" --marketing 2.0.4 --build 5 --dmg "$TMP/fake.dmg" --appcast "$TMP/e.xml" \
  --replace-enclosure-version 9.9.9; then
  fail "replace missing should fail"
fi
pass "replace missing"

echo "All script tests passed."
