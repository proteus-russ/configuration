#!/usr/bin/env python3
"""Strip comments from source, leaving code and literals intact.

Used by the doc-comment-style skill to prove a doc-comment sweep changed no code:
strip both the before and after versions and diff the results. Any difference
means code moved, not just comments.

Languages, chosen by file extension, so pass real filenames:
  .java .groovy .scala .swift .dart   C-like; Kotlin, Scala, Swift, Dart and
  .kt .kts                            Groovy block comments nest, Java's do not
  .js .mjs .cjs .jsx .ts .mts .cts .tsx  JavaScript: template literals with
                                      nested ${} and regex literals survive
  .css .scss .sass .less              /* */ only; // too for scss/sass/less
  .vue                                top-level <template>, <script> and <style>
                                      blocks each stripped in their own syntax

Usage:
    comment_strip.py FILE...            # print stripped source to stdout
    comment_strip.py --compare A B      # exit 0 if code identical, 1 if not
    comment_strip.py --git FILE...      # compare each file against git HEAD
    comment_strip.py --self-test
"""
import re
import subprocess
import sys

NESTING_SUFFIXES = ('.kt', '.kts', '.scala', '.swift', '.dart', '.groovy')
JS_SUFFIXES = ('.js', '.mjs', '.cjs', '.jsx', '.ts', '.mts', '.cts', '.tsx')
CSS_SUFFIXES = ('.css', '.scss', '.sass', '.less')


def language(path):
    p = path.lower()
    if p.endswith('.vue'):
        return 'vue'
    if p.endswith(JS_SUFFIXES):
        return 'js'
    if p.endswith(CSS_SUFFIXES):
        return 'scss' if p.endswith(('.scss', '.sass', '.less')) else 'css'
    if p.endswith(NESTING_SUFFIXES):
        return 'nested'
    return 'clike'


def strip(src, lang='clike'):
    if lang == 'vue':
        return strip_vue(src)
    if lang == 'js':
        return strip_js(src)
    if lang in ('css', 'scss'):
        return strip_css(src, line_comments=(lang == 'scss'))
    return strip_clike(src, nested=(lang == 'nested'))


def _newlines(text):
    return '\n' * text.count('\n')


# --- C-like: Java, Kotlin, Groovy ------------------------------------------

def strip_clike(src, nested=False):
    """Remove // and /* */ comments. String, char and text-block contents survive."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ''
        if c == '/' and nxt == '/':
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if c == '/' and nxt == '*':
            i = _skip_block(src, i, out, nested)
            continue
        if src.startswith('"""', i):
            j = src.find('"""', i + 3)
            j = n if j < 0 else j + 3
            out.append(src[i:j])
            i = j
            continue
        if c in '"\'':
            i = _copy_quoted(src, i, out, c)
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def _skip_block(src, i, out, nested):
    """Skip a /* */ comment starting at i. Keep newlines so line numbers hold."""
    n = len(src)
    depth = 1
    i += 2
    while i < n and depth > 0:
        if nested and src.startswith('/*', i):
            depth += 1
            i += 2
        elif src.startswith('*/', i):
            depth -= 1
            i += 2
        else:
            if src[i] == '\n':
                out.append('\n')
            i += 1
    return i


def _copy_quoted(src, i, out, quote):
    """Copy a quoted literal starting at i, honouring backslash escapes."""
    n = len(src)
    out.append(src[i])
    i += 1
    while i < n:
        c = src[i]
        out.append(c)
        if c == '\\' and i + 1 < n:
            out.append(src[i + 1])
            i += 2
            continue
        i += 1
        if c == quote or c == '\n':
            break
    return i


# --- JavaScript / TypeScript --------------------------------------------------

_REGEX_PREV_CHARS = set('(,=:[!&|?{};+-*%<>~^')
_REGEX_PREV_WORDS = {'return', 'typeof', 'case', 'in', 'of', 'instanceof', 'new',
                     'delete', 'void', 'throw', 'else', 'do', 'yield', 'await'}


def strip_js(src):
    """Remove // and /* */ comments from JavaScript or TypeScript.

    Strings, template literals (including code inside ${}) and regex literals
    survive. Whether a / starts a regex or is division is decided from the last
    significant token, the usual heuristic; it is right for ordinary code.
    """
    out = []
    i, n = 0, len(src)
    # Stack of open template literals. Each entry is the brace depth of the
    # ${ } expression currently open inside that literal, or None while in
    # the literal's text.
    tpl = []
    last_char = ''
    last_word = ''
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ''
        in_tpl_text = tpl and tpl[-1] is None
        if in_tpl_text:
            if c == '`':
                out.append(c)
                tpl.pop()
                i += 1
                last_char = '`'
            elif c == '$' and nxt == '{':
                out.append('${')
                tpl[-1] = 0
                i += 2
                last_char = '{'
            elif c == '\\' and i + 1 < n:
                out.append(src[i:i + 2])
                i += 2
            else:
                out.append(c)
                i += 1
            continue
        if c == '/' and nxt == '/':
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if c == '/' and nxt == '*':
            i = _skip_block(src, i, out, False)
            continue
        if c == '`':
            out.append(c)
            tpl.append(None)
            i += 1
            last_char = '`'
            continue
        if c in '"\'':
            i = _copy_quoted(src, i, out, c)
            last_char = c
            last_word = ''
            continue
        if c == '/' and _regex_allowed(last_char, last_word):
            i = _copy_regex(src, i, out)
            last_char = '/'
            last_word = ''
            continue
        if tpl and tpl[-1] is not None:
            if c == '{':
                tpl[-1] += 1
            elif c == '}':
                if tpl[-1] == 0:
                    out.append(c)
                    tpl[-1] = None
                    i += 1
                    continue
                tpl[-1] -= 1
        out.append(c)
        i += 1
        if c.isalnum() or c in '_$':
            last_word = (last_word + c) if (last_char.isalnum() or last_char in '_$') else c
            last_char = c
        elif not c.isspace():
            last_char = c
            last_word = ''
    return ''.join(out)


def _regex_allowed(last_char, last_word):
    if last_char == '':
        return True
    if last_word in _REGEX_PREV_WORDS:
        return True
    if last_char.isalnum() or last_char in '_$)]':
        return False
    return last_char in _REGEX_PREV_CHARS


def _copy_regex(src, i, out):
    n = len(src)
    out.append('/')
    i += 1
    in_class = False
    while i < n:
        c = src[i]
        if c == '\n':
            break
        out.append(c)
        i += 1
        if c == '\\' and i < n:
            out.append(src[i])
            i += 1
        elif c == '[':
            in_class = True
        elif c == ']':
            in_class = False
        elif c == '/' and not in_class:
            while i < n and src[i].isalpha():
                out.append(src[i])
                i += 1
            break
    return i


# --- CSS ----------------------------------------------------------------------

def strip_css(src, line_comments=False):
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ''
        if c == '/' and nxt == '*':
            i = _skip_block(src, i, out, False)
            continue
        if line_comments and c == '/' and nxt == '/':
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if c in '"\'':
            i = _copy_quoted(src, i, out, c)
            continue
        if src.startswith('url(', i):
            j = src.find(')', i)
            j = n if j < 0 else j + 1
            out.append(src[i:j])
            i = j
            continue
        out.append(c)
        i += 1
    return ''.join(out)


# --- Vue single-file components ----------------------------------------------

_VUE_BLOCK = re.compile(
    r'^<(template|script|style)(\b[^>]*)>(.*?)^</\1>', re.M | re.S)
_HTML_COMMENT = re.compile(r'<!--.*?-->', re.S)


def strip_vue(src):
    """Strip each top-level block in its own syntax. Custom blocks pass through."""
    def repl(m):
        kind, attrs, body = m.group(1), m.group(2), m.group(3)
        if kind == 'template':
            body = _HTML_COMMENT.sub(lambda c: _newlines(c.group(0)), body)
        elif kind == 'script':
            body = strip_js(body)
        else:
            lang = re.search(r'lang=["\']?(\w+)', attrs)
            body = strip_css(body, line_comments=bool(
                lang and lang.group(1) in ('scss', 'sass', 'less', 'stylus')))
        return '<%s%s>%s</%s>' % (kind, attrs, body, kind)
    return _VUE_BLOCK.sub(repl, src)


# --- Driver -------------------------------------------------------------------

def normalise(src, lang):
    """Collapse whitespace so reflowed code is still recognised as unchanged."""
    return ' '.join(strip(src, lang).split())


def read(path):
    with open(path, encoding='utf-8', errors='replace') as fh:
        return fh.read()


def compare(name, before, after):
    lang = language(name)
    if normalise(before, lang) == normalise(after, lang):
        print('  CODE UNCHANGED  %s' % name)
        return True
    print('  CODE CHANGED    %s' % name)
    return False


def self_test():
    cases = [
        ('js', 'const u = "http://x" // c\nconst t = `a ${b /* c */ + `${d}`} // not`\n',
               'const u = "http://x" \nconst t = `a ${b  + `${d}`} // not`\n'),
        ('js', 'const r = /https?:\\/\\/[/*]+/g; x = a / b // c\n',
               'const r = /https?:\\/\\/[/*]+/g; x = a / b \n'),
        ('js', 'return /\\/\\//.test(s) /* k */\n', 'return /\\/\\//.test(s) \n'),
        ('js', 'x = y /2/ z // d\n', 'x = y /2/ z \n'),
        ('vue', '<template>\n  <!-- c -->\n  <template v-if="a"><b>//</b></template>\n</template>\n'
                '<script setup lang="ts">\n// c\nconst s = `<!-- ${x} -->`\n</script>\n'
                '<style scoped lang="scss">\n/* c */ a { b: url(http://x) } // d\n</style>\n',
                '<template>\n  \n  <template v-if="a"><b>//</b></template>\n</template>\n'
                '<script setup lang="ts">\n\nconst s = `<!-- ${x} -->`\n</script>\n'
                '<style scoped lang="scss">\n a { b: url(http://x) } \n</style>\n'),
        ('css', 'a { b: url(http://x) } /* c */\n', 'a { b: url(http://x) } \n'),
        ('nested', 'val s = "/*" /* a /* b */ c */ + 1\n', 'val s = "/*"  + 1\n'),
        ('clike', 'String s = "//"; // c\nchar c = \'"\'; /* d\n */ int x;\n',
                  'String s = "//"; \nchar c = \'"\'; \n int x;\n'),
    ]
    bad = 0
    for lang, src, want in cases:
        got = strip(src, lang)
        if got != want:
            bad += 1
            print('FAIL %s\n  src  %r\n  want %r\n  got  %r' % (lang, src, want, got))
    print('%d/%d self-tests passed' % (len(cases) - bad, len(cases)))
    return 1 if bad else 0


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    if argv[0] == '--self-test':
        return self_test()
    if argv[0] == '--compare':
        if len(argv) != 3:
            print('--compare needs exactly two files')
            return 2
        return 0 if compare(argv[2], read(argv[1]), read(argv[2])) else 1
    if argv[0] == '--git':
        ok = True
        for path in argv[1:]:
            shown = subprocess.run(['git', 'show', 'HEAD:./%s' % path],
                                   capture_output=True, text=True)
            if shown.returncode != 0:
                print('  NEW FILE        %s (nothing to compare)' % path)
                continue
            ok = compare(path, shown.stdout, read(path)) and ok
        return 0 if ok else 1
    for path in argv:
        sys.stdout.write(strip(read(path), language(path)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
