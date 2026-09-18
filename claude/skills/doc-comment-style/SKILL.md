---
name: doc-comment-style
description: Sweep existing doc comments into house style. Covers Javadoc (.java), KDoc (.kt), JSDoc/TSDoc (.ts, .js) and all three comment kinds in Vue single-file components (.vue). Use when the user asks to fix, normalise, tidy or retrofit javadoc/KDoc/JSDoc/doc comments across a file, package, module or SPA directory, or to strip em-dashes and AI-sounding prose from comments. Not for adding missing doc comments.
argument-hint: "path, package or module to sweep (defaults to the current diff)"
---

# Doc comment style sweep

Rewrite existing doc comments to house style. Works on Javadoc (`.java`), KDoc
(`.kt`), JSDoc/TSDoc (`.ts`, `.js`) and Vue single-file components (`.vue`), where
the `<script>` block is JSDoc, the `<template>` block has `<!-- -->` comments and
the `<style>` block has CSS comments. **Comments only. This skill never changes
code.**

Two things this is not:

- Not for **adding** doc comments where none exist. That needs knowledge of the
  code's behaviour, not of its style. Say so and stop.
- Not for **correcting** doc comments that are factually wrong. Report those and
  leave them. A style sweep that silently rewrites a false claim into a
  differently-false claim is worse than the original.

## The rule that governs everything else

The standard lives in `~/.claude/rules/doc-comments.md`: prose and content are
fixed, markup and spacing are derived per language and per project. This skill
does not restate it. Read the rule if it is not already in context.

The distinction is load-bearing. A codebase with machine-generated comments has a
*majority* style that is exactly what the sweep exists to remove. Measure to learn
the markup; never to learn the prose. The project's CLAUDE.md may say which of its
own trees are and are not safe references.

## Phase 0: Bound the scope

Take the target from the argument. With no argument, use the current diff
(`git diff HEAD --name-only`, filtered to `.java`, `.kt`, `.ts`, `.js`, `.vue`).

Count the doc comments in range first:

```bash
python3 - <<'PY'
import re, glob, collections
pat = re.compile(r'/\*\*.*?\*/', re.S)
n = collections.Counter()
tpl = re.compile(r'<!--.*?-->', re.S)
for ext in ('java', 'kt', 'ts', 'js', 'vue'):
    for f in glob.glob('<target>/**/*.' + ext, recursive=True):
        if '/build/' in f or '/node_modules/' in f or '.generated.' in f: continue
        src = open(f, encoding='utf-8', errors='replace').read()
        n[ext] += len(pat.findall(src))
        if ext == 'vue': n['vue <!-- -->'] += len(tpl.findall(src))
print('doc comments in range:', dict(n), 'total', sum(n.values()))
PY
```

**Refuse an unbounded sweep.** Above roughly 150 doc comments, report the count,
propose an ordering (files with the most mechanical violations first), and ask
which batch to take. A bulk comment rewrite that cannot be reviewed is worse than
stale comments.

## Phase 1: Read the codified standard

Do not infer formatting a config file already states. **If the project's CLAUDE.md
already records what is enforced and the measured markup habits, take those as
the result of Phases 1 and 2 and go to Phase 3.** Re-measure only when the target
is a module the CLAUDE.md does not cover.

```bash
# Java: IntelliJ doc-comment formatting
grep -rhoE 'JD_[A-Z_]+" value="[^"]*"' .idea/codeStyles/ .idea/codeStyleSettings.xml 2>/dev/null | sort -u
# Java: checkstyle javadoc modules, their scopes and severities
grep -rn -A4 'Javadoc' $(find . -name 'checkstyle*.xml' -not -path '*/build/*' | head -3) 2>/dev/null
# IDE inspection severities
grep -oE '<inspection_tool class="[A-Za-z]*[Jj]ava[Dd]oc[A-Za-z]*"[^>]*' .idea/inspectionProfiles/*.xml 2>/dev/null
# Kotlin: ktlint / detekt / Dokka config
ls .editorconfig detekt*.yml ktlint* 2>/dev/null; grep -rn "dokka" --include="*.gradle*" . 2>/dev/null | head -3
# TypeScript / Vue: JSDoc lint plugins, comment-affecting ESLint rules, prettier
grep -nE 'jsdoc|tsdoc|comment' <spa>/eslint.config.* <spa>/.eslintrc* 2>/dev/null
grep -nE 'jsdoc|tsdoc|typedoc' <spa>/package.json; cat <spa>/prettier.config.* 2>/dev/null
```

Prettier does not reflow comment prose and no ESLint preset checks JSDoc unless
`eslint-plugin-jsdoc` or `@microsoft/tsdoc` is listed. Without one of those the
TS side is like KDoc: nothing fails a build, so verification is by eye plus the
IDE's `{@link}` resolution.

Java `JD_*` keys worth knowing:

| Key | Effect when true |
| --- | --- |
| `JD_ADD_BLANK_AFTER_PARM_COMMENTS` | blank line after the whole `@param` group |
| `JD_ADD_BLANK_AFTER_RETURN` | blank line after `@return` |
| `JD_ALIGN_PARAM_COMMENTS` | descriptions aligned in columns |
| `JD_P_AT_EMPTY_LINES` | `<p>` inserted on blank lines automatically |
| `JD_DO_NOT_WRAP_ONE_LINE_COMMENTS` | `/** Short. */` stays on one line |

Checkstyle `scope`/`accessModifiers` on `JavadocMethod`/`JavadocType`/
`JavadocVariable` says which members are *required* to carry doc comments. Do not
add tags to members outside that scope for symmetry. `authorFormat` gives the
required `@author` shape.

## Phase 2: Measure the module for markup only

Run over the module containing the target. A module is the unit of consistency,
not a repo:

```bash
python3 - <<'PY'
import re, glob, collections, sys
root, ext = '<target>', 'kt'   # or 'java', 'ts', 'vue'
blocks = []
for f in glob.glob('%s/**/*.%s' % (root, ext), recursive=True):
    if '/build/' in f or '/node_modules/' in f or '.generated.' in f: continue
    blocks += re.findall(r'/\*\*.*?\*/', open(f, encoding='utf-8', errors='replace').read(), re.S)
j = ' '.join(blocks)
HTML = {'p','ul','ol','li','br','code','b','i','tt','dl','dt','dd','a','pre','em','strong'}
print('blocks:', len(blocks))
print('single-line: %d (%.0f%%)' % (sum(1 for b in blocks if '\n' not in b),
      100.0 * sum(1 for b in blocks if '\n' not in b) / max(1, len(blocks))))
# Filter to real HTML: a bare `<(\w+)>` regex also counts placeholder prose
# like <filename> or <other stuff> and makes a clean file set look like HTML.
print('html tags:', collections.Counter(
    t for t in re.findall(r'</?([a-z]+)[ />]', j) if t in HTML).most_common(8) or 'none')
print('{@link}: %d   {@code}: %d   [Ref]: %d   `code`: %d   "- " bullets: %d' % (
    len(re.findall(r'\{@link', j)), len(re.findall(r'\{@code', j)),
    len(re.findall(r'\[[A-Z][A-Za-z0-9_.]*\]', j)), len(re.findall(r'`[^`\n]+`', j)),
    len(re.findall(r'^\s*\*\s+[-*]\s', j, re.M))))
print('@param: %d   @param {type}: %d   @returns: %d   @return: %d' % (
    len(re.findall(r'@param\b', j)), len(re.findall(r'@param\s+\{', j)),
    len(re.findall(r'@returns\b', j)), len(re.findall(r'@return\s', j))))
# prose HEALTH, not prose convention: high numbers mean this file set needs the
# sweep, and must not be used as a reference for how to write.
first = collections.Counter()
for b in blocks:
    body = re.sub(r'^\s*\*\s?', '', b.strip('/*').strip(), flags=re.M).strip()
    m = re.match(r'([A-Za-z]+)', body)
    if m: first[m.group(1)] += 1
print('openers:', first.most_common(8))
print('em-dash blocks: %d (%.1f%%)' % (
    sum(1 for b in blocks if '&mdash;' in b or '—' in b),
    100.0 * sum(1 for b in blocks if '&mdash;' in b or '—' in b) / max(1, len(blocks))))
PY
```

Read the markup numbers and follow them. A construct at **zero** occurrences is
not house style however much you like it. This is how `<dl>/<dt>/<dd>` and HTML
in KDoc get introduced by mistake.

Read the prose numbers as a **health check on the target**, not as a convention to
adopt. A high em-dash rate or third-person-dominant openers means more to fix, not
a style to match.

Then read 3-5 whole doc comments from a **known-good** reference in the same
language. Counts give the surface; reading gives the register.

## Phase 3: Find candidates

**Anchor every pattern to a comment line.** `^[[:space:]]*(\*|/\*\*|//)` covers doc
comments, their continuation lines, and line comments, while excluding string
literals. Unanchored greps match HTML in email templates, `joinToString("<br>")`
and test fixtures, and drown the real hits.

Prose, all languages. The anchor also takes `<!--` so Vue template comments are
in range:

```bash
C='^[[:space:]]*(\*|/\*\*|//|<!--)'
I=('--include=*.java' '--include=*.kt' '--include=*.ts' '--include=*.js' '--include=*.vue' '--exclude=*.generated.*')
grep -rnE "${I[@]}" "$C.*(&mdash;|—)"                        <target>
grep -rnE "${I[@]}" "$C.* -- "                               <target>
grep -rnE "${I[@]}" "^[[:space:]]*\*[[:space:]]*(Gets|Sets|Returns|Creates) " <target>
grep -rniE "${I[@]}" "$C.*(simply|seamlessly|powerful|robust|leverages)"      <target>
```

A Vue template comment can span lines; only its first line carries `<!--`, so
also run the em-dash grep unanchored on `.vue` files and filter by eye.

Markup, Java:

```bash
grep -rnE "$C.*(<dl>|<dt>|<dd>|<code>|<tt>)" --include="*.java" <target>
```

Markup, Kotlin. HTML and Javadoc inline tags in KDoc are always wrong, whatever
the local count says, because they render as literal text:

```bash
grep -rnE "$C.*(<p>|<ul>|<li>|<br>|<code>|<b>|<i>)" --include="*.kt" <target>
grep -rnE "$C.*\{@(link|code|literal)"              --include="*.kt" <target>
```

Markup, TypeScript and Vue. `{@code}` does not exist in JSDoc, `@param {Type}` is
noise under TypeScript, `@return` should be `@returns`, and a tag that only
restates the signature is deleted (the rule's Content section; Javadoc is the
one exception):

```bash
T=('--include=*.ts' '--include=*.js' '--include=*.vue' '--exclude=*.generated.*')
grep -rnE "${T[@]}" "$C.*(<p>|<ul>|<li>|<br>|<code>|<b>|<i>)" <target>
grep -rnE "${T[@]}" "$C.*\{@(code|literal)"                   <target>
grep -rnE "${T[@]}" "$C.*@param[[:space:]]+\{"                <target>
grep -rnE "${T[@]}" "$C.*@return[[:space:]]"                   <target>
grep -rnE "${T[@]}" "$C.*@(param|returns)[[:space:]]+[A-Za-z_]*[[:space:]]*(the|a|an) [a-z]+\.?[[:space:]]*$" <target>
```

Two residual false positives to expect, both needing a human read rather than a
better pattern:

- Comment prose that legitimately *discusses* markup ("Outlook pretends `<p>` tags
  have no margins"). Mentioning a tag is not using one.
- A trailing `// comment` after code on the same line is not matched by the anchor.
  If the target is small, also skim `grep -rn "//.*—" <target>` and filter URLs and
  literals by eye.

Judgement, from reading: compound sentences held together by a dash, colon or
semicolon; a caveat buried mid-paragraph that belongs behind `NOTE:`; tag spacing
that disagrees with Phase 1; one-line comments expanded to three lines or vice
versa.

## Phase 4: Rewrite

Hard rules:

1. **Never touch code.** Not whitespace, not imports, not a stray semicolon.
2. **Never invent behaviour.** Rephrase claims already present, or claims you
   verified against the code *in this session*. If you cannot tell whether a
   sentence is true, keep its wording.
3. **Lose no information.** If a rewrite drops a detail, the rewrite is wrong.
   Terse is the goal; lossy is not.
4. Leave `@author`, `@since`, `@see`, `@serial`, `@deprecated`, `@suppress` and
   `@sample` bodies alone unless they are what the user asked you to change.
5. Do not renumber, reorder or delete tags. A wrong `@param` name is a Phase 5
   report, not a silent fix. The rule lists the Kotlin-only tags; never drop one.

Converting markup when a KDoc block carries Javadoc habits:

- `<p>text</p>` becomes a blank line before `text`.
- `{@link Foo#bar}` becomes `[Foo.bar]`. Verify the target resolves; KDoc silently
  renders a broken reference as plain text rather than failing the build, so a bad
  conversion is invisible.
- `{@code x}` and `<code>x</code>` become `` `x` ``.
- `<ul><li>a</li></ul>` becomes `- a` bullets.

Converting markup when a JSDoc block carries Javadoc habits: the same table, except
`{@link Foo#bar}` becomes `{@link Foo.bar}` (TypeScript resolves it) or plain
`` `bar` `` when the reader does not need to jump. `@param {Type} name` loses the
braces. A bare `@param name the name` is deleted outright, and if the block is then
empty, the whole block goes.

Vue templates: fix prose only. Keep a template comment on one line where the
rewrite allows. Never move a comment across a block boundary.

Rewriting prose: apply the three dash cases from the rule. Do not reach for a
comma by default; most single dashes are a spliced sentence.

Keep the subject concrete. Where the original says nothing, leave it saying
nothing. A style sweep is not a licence to pad.

## Phase 5: Verify

**The code-unchanged check is not optional.** It is the reason this sweep is safe
to run in bulk:

```bash
python3 ~/.claude/skills/doc-comment-style/comment_strip.py --git <each changed file>
```

It strips comments from the `HEAD` version and the working version, normalises
whitespace, and reports `CODE UNCHANGED` or `CODE CHANGED` per file. String, char
and raw-string/text-block contents survive, so a literal containing `/*` or `//`
does not confuse it. In TypeScript, template literals with nested `${}` and regex
literals survive too; in `.vue` each top-level block is stripped in its own syntax
(`<!-- -->`, JSDoc, CSS). Kotlin block comments nest and Java's do not; the tool
switches on the file extension, so **pass real filenames**. Any `CODE CHANGED` on
a file you only meant to comment in means you edited code. Find it and revert
that part. Files new since `HEAD` report `NEW FILE`.

Then, in the project's own terms:

```bash
./gradlew :<module>:javadoc     # Java: must stay clean; unresolved {@link} is an error
./gradlew :<module>:dokkaHtml   # Kotlin, if Dokka is configured
npm run lint && npm run type-check   # TS/Vue, from the SPA root: comment edits
                                     # can still trip eslint-disable placement
```

For KDoc without Dokka, and for JSDoc without a jsdoc lint plugin, there is no
build-time reference check, so **spot-check converted `[Ref]` and `{@link}` links
by eye**. That is the one thing nothing else will catch. In Vue, also check that
an `<!-- eslint-disable-next-line … -->` comment still sits directly above the
line it excuses.

Finally check line length against the project limit, and re-run the Phase 2
measurement to confirm the numbers moved as intended.

## Report

- Files swept, doc comments changed, before/after counts per mechanical category.
- The `CODE UNCHANGED` result for every file.
- What you left alone and why. Flag anything you suspect is *factually
  wrong*, which is the most valuable output of a sweep and must not be buried.
- Anything still out of scope, with the count, so the next batch is obvious.
