# Sparkle Appcast Versioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `scripts/update-appcast.sh` that writes correct Sparkle build/`shortVersionString`/`length` into appcast XML, fix the live 2.0.4 gh-pages entry to `version=5`, and update release docs so marketing versions are never used as `sparkle:version` again.

**Architecture:** A bash script mutates a local `appcast.xml` (insert or `--replace-enclosure-version`). Fixture-based shell tests cover insert/replace/failure paths. Live gh-pages correction is a separate HITL push after the script exists. App Swift code (`UpdateService`) is unchanged; Sparkle standard UI handles download progress and install.

**Tech Stack:** bash, `stat`/`grep`/`sed` or Python3 for safe XML-ish editing (prefer Python3 stdlib for insert/replace reliability on macOS), XCTest not used for scripts; docs in Markdown.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-16-sparkle-appcast-versioning-design.md`
- `sparkle:version` = integer build only (e.g. `5`); `sparkle:shortVersionString` = marketing (e.g. `2.0.4`)
- Do not rewrite historical marketing-style `sparkle:version` values except via `--replace-enclosure-version`
- Do not auto `git commit` / `git push` / touch remote `gh-pages` without explicit user authorization
- Do not implement custom Sparkle UI, `generate_appcast`, or EdDSA signing
- Default DMG URL: `https://github.com/nmsn/quota-bar/releases/download/v{marketing}/QuotaBar-{marketing}.dmg`
- Known live fix: replace enclosure `sparkle:version="2.0.4"` → `5` + `shortVersionString="2.0.4"`, length `1407629`
- Repo HITL: user must authorize push to `gh-pages` and any PR

---

## File Structure

```
scripts/
  update-appcast.sh                 # Create: CLI entry
  update_appcast.py                 # Create: insert/replace logic (called by shell)
  tests/
    test-update-appcast.sh          # Create: fixture-driven tests
    fixtures/
      appcast-sample.xml            # Create: sample with marketing-style versions
docs/
  release-process.md                # Modify: appcast step + checklist
  sparkle-integration.md            # Modify: field table + script usage
  superpowers/specs/...-design.md   # Already committed
```

Prefer **Python3** for XML mutation (stdlib `xml.etree` struggles with namespaces; use careful regex/string ops on well-known appcast shape OR ElementTree with Sparkle namespace). Plan locks: implement mutation in `scripts/update_appcast.py`; thin `update-appcast.sh` parses args and invokes it.

---

### Task 1: Fixture tests + `update_appcast.py` MVP (insert + failures)

**Files:**
- Create: `scripts/update_appcast.py`
- Create: `scripts/update-appcast.sh`
- Create: `scripts/tests/fixtures/appcast-sample.xml`
- Create: `scripts/tests/test-update-appcast.sh`

**Interfaces:**
- Consumes: none
- Produces: CLI  
  `python3 scripts/update_appcast.py --marketing M --build B --dmg PATH --appcast PATH [--url U] [--date D] [--title T] [--replace-enclosure-version OLD]`  
  exit 0 on success; non-zero on validation errors

- [ ] **Step 1: Write fixture appcast**

Create `scripts/tests/fixtures/appcast-sample.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>QuotaBar Updates</title>
    <link>https://nmsn.github.io/quota-bar/appcast.xml</link>
    <item>
      <title>Version 2.0.3</title>
      <pubDate>Wed, 03 Jun 2026 15:22:00 +0800</pubDate>
      <enclosure url="https://github.com/nmsn/quota-bar/releases/download/v2.0.3/QuotaBar-2.0.3.dmg" sparkle:version="2.0.3" length="1776670" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

- [ ] **Step 2: Write failing tests**

Create `scripts/tests/test-update-appcast.sh` (executable):

```bash
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
import sys,re
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
```

**Note for implementer:** Fix the broken `python3` placeholder block in the test file above when writing the real file — the crafted `cat > "$TMP/d.xml"` heredoc is the intended setup; delete the dead `python3` stub with `Path("$TMP/d.xml".replace...)`.

- [ ] **Step 3: Run tests — expect FAIL (script missing)**

```bash
chmod +x scripts/tests/test-update-appcast.sh
./scripts/tests/test-update-appcast.sh
```

Expected: FAIL — `update-appcast.sh` not found or not executable.

- [ ] **Step 4: Implement `scripts/update_appcast.py`**

Requirements to encode:

1. Parse argv as listed in Interfaces.
2. Validate `--build` is positive integer (`^[0-9]+$`).
3. Validate DMG exists and `os.path.getsize(dmg) > 0`.
4. Read appcast text as UTF-8.
5. Collect all `sparkle:version="..."` values via regex.
6. If `--replace-enclosure-version OLD`:
   - Find enclosure with `sparkle:version="OLD"` (if multiple, prefer one whose `url` contains `QuotaBar-{marketing}.dmg` or title sibling — for MVP: first match where surrounding item title contains marketing OR url contains marketing).
   - Replace that enclosure’s attributes: set version to build, set/add `sparkle:shortVersionString="{marketing}"`, set `length` to size, keep url/type unless `--url` provided then update url.
   - If no match: `sys.exit(1)`.
7. Else insert mode:
   - If any version equals build (string): exit 1.
   - Among versions matching `^[0-9]+$`, if any `int(v) >= build`: exit 1.
   - If any version contains `.`: print warning to stderr once.
   - Build item XML string; insert immediately after `<channel>...` opening content — specifically before the first `<item>`.
8. Write appcast atomically (write temp + replace).
9. Print summary line to stdout: `marketing=... build=... length=... url=...`

Use regex carefully; do not require `lxml`. Namespace prefix `sparkle:` stays as literal attribute names in the file.

- [ ] **Step 5: Implement thin `scripts/update-appcast.sh`**

```bash
#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT/scripts/update_appcast.py" "$@"
```

`chmod +x scripts/update-appcast.sh`

- [ ] **Step 6: Run tests — expect PASS**

```bash
./scripts/tests/test-update-appcast.sh
```

Expected: `All script tests passed.`

- [ ] **Step 7: Commit (only if user authorizes)**

```bash
git add scripts/update_appcast.py scripts/update-appcast.sh scripts/tests/
git commit -m "$(cat <<'EOF'
feat: add update-appcast script with fixture tests

EOF
)"
```

---

### Task 2: Documentation updates

**Files:**
- Modify: `docs/sparkle-integration.md`
- Modify: `docs/release-process.md`
- Optionally modify: `CLAUDE.md` (short pointer only)

**Interfaces:**
- Consumes: script CLI from Task 1
- Produces: documented field table + release checklist items

- [ ] **Step 1: Update `docs/sparkle-integration.md`**

Replace the sample enclosure that uses `sparkle:version="2.0.2"` as marketing with:

```xml
<item>
  <title>Version 2.0.4</title>
  <pubDate>Thu, 16 Jul 2026 10:58:00 +0800</pubDate>
  <enclosure url="https://github.com/nmsn/quota-bar/releases/download/v2.0.4/QuotaBar-2.0.4.dmg"
             sparkle:version="5"
             sparkle:shortVersionString="2.0.4"
             length="1407629"
             type="application/octet-stream"/>
</item>
```

Add a section **Version fields**:

| Field | Meaning | Example |
|-------|---------|---------|
| `sparkle:version` / `CFBundleVersion` | Monotonic build integer | `5` |
| `sparkle:shortVersionString` / `CFBundleShortVersionString` | Marketing version | `2.0.4` |

Add **Updating appcast with script** showing insert and `--replace-enclosure-version` examples. Note: never put marketing X.Y.Z into `sparkle:version`. Note Pages CDN vs `raw.githubusercontent.com/nmsn/quota-bar/gh-pages/appcast.xml`.

- [ ] **Step 2: Update `docs/release-process.md`**

After DMG upload step, add:

```markdown
### N. Update appcast (gh-pages)

1. Confirm the Release `.app` / DMG embeds the intended MARKETING_VERSION and CURRENT_PROJECT_VERSION
   (`defaults read /path/to/QuotaBar.app/Contents/Info CFBundleVersion`).
2. Check out gh-pages worktree / clone path containing `appcast.xml`.
3. Run:

```bash
./scripts/update-appcast.sh \
  --marketing X.Y.Z \
  --build N \
  --dmg dist/QuotaBar-X.Y.Z.dmg \
  --appcast /path/to/gh-pages/appcast.xml
```

4. Review diff; after human approval, commit and push `gh-pages`.
5. Verify via raw URL that the new item shows integer `sparkle:version` and `shortVersionString`.
```

Update checklist:

- [ ] `sparkle:version` is integer build (not marketing)
- [ ] `sparkle:shortVersionString` set
- [ ] `length` matches DMG byte size
- [ ] raw appcast verified

- [ ] **Step 3: Optional one-liner in `CLAUDE.md` Sparkle section**

Add: use `scripts/update-appcast.sh`; `sparkle:version` must be `CURRENT_PROJECT_VERSION`.

- [ ] **Step 4: Commit (only if user authorizes)**

```bash
git add docs/sparkle-integration.md docs/release-process.md CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: document Sparkle build vs marketing version and appcast script

EOF
)"
```

---

### Task 3: Fix live gh-pages 2.0.4 entry (HITL)

**Files:**
- Modify on `gh-pages` only: `appcast.xml` (via worktree)

**Interfaces:**
- Consumes: `update-appcast.sh` from Task 1; DMG at `dist/QuotaBar-2.0.4.dmg` or download from Release

- [ ] **Step 1: Ensure DMG available locally**

```bash
test -f dist/QuotaBar-2.0.4.dmg || gh release download v2.0.4 -p 'QuotaBar-2.0.4.dmg' -D dist
stat -f %z dist/QuotaBar-2.0.4.dmg
```

Expected size: `1407629`

- [ ] **Step 2: Worktree + replace**

```bash
WT="$(git rev-parse --show-toplevel)/.worktrees/gh-pages-appcast-fix"
git fetch origin gh-pages
git worktree add "$WT" gh-pages
./scripts/update-appcast.sh \
  --marketing 2.0.4 \
  --build 5 \
  --dmg dist/QuotaBar-2.0.4.dmg \
  --appcast "$WT/appcast.xml" \
  --replace-enclosure-version 2.0.4
grep -n '2.0.4' "$WT/appcast.xml" | head -20
```

Expected: enclosure shows `sparkle:version="5"` and `sparkle:shortVersionString="2.0.4"` and `length="1407629"`.

- [ ] **Step 3: Show diff to user; only after explicit authorization**

```bash
cd "$WT" && git diff appcast.xml
# USER MUST APPROVE, then:
git add appcast.xml
git commit -m "fix: set Sparkle build 5 for v2.0.4 appcast entry"
git push origin gh-pages
```

- [ ] **Step 4: Verify raw feed**

```bash
curl -sL https://raw.githubusercontent.com/nmsn/quota-bar/gh-pages/appcast.xml | head -20
```

Expected: first item enclosure `sparkle:version="5"`.

- [ ] **Step 5: Remove worktree**

```bash
git worktree remove "$WT"
```

- [ ] **Step 6: No main-branch commit required for this task** (gh-pages only). Record in PR/body if feature branch PR is opened for Tasks 1–2.

---

### Task 4: Manual acceptance + PR for script/docs

**Files:** none new on main beyond Tasks 1–2

- [ ] **Step 1: Manual check on machine still running 2.0.3 build 4**

Right-click → Check for Updates. Expected: Sparkle offers update (download progress UI), **not** “You’re up to date” claiming 2.0.4 while running 2.0.3.

If Pages CDN still stale, confirm raw URL first; wait/retry.

- [ ] **Step 2: Open PR for `feat/sparkle-appcast-versioning` (script + docs + design)**

Only after user authorizes push/PR:

```bash
git push -u origin HEAD
gh pr create --title "fix: Sparkle appcast build versioning + update script" --body "$(cat <<'EOF'
## Summary
- Add `scripts/update-appcast.sh` (+ Python helper) with fixture tests
- Document build vs marketing Sparkle fields in release/Sparkle docs
- Live `gh-pages` fix for v2.0.4 (`sparkle:version=5`) done separately on gh-pages

## Test plan
- [ ] `./scripts/tests/test-update-appcast.sh`
- [ ] raw appcast shows version 5 + shortVersionString 2.0.4
- [ ] QuotaBar 2.0.3 (build 4) Check for Updates offers install UI

EOF
)"
```

---

## Self-Review (plan vs spec)

| Spec requirement | Task |
|------------------|------|
| Script insert + length + build/shortVersionString | Task 1 |
| Monotonic / duplicate / missing DMG failures | Task 1 tests |
| `--replace-enclosure-version` | Task 1 |
| Do not rewrite unrelated history | Task 1 insert path |
| Docs field table + checklist | Task 2 |
| Live fix 2.0.4 → build 5 | Task 3 |
| Standard Sparkle UI / no custom progress | Explicit non-goal; no Swift changes |
| HITL for gh-pages push | Task 3 Step 3 |
| Manual acceptance | Task 4 |

No TBD placeholders remain after implementer removes the noted dead stub in the test template.
