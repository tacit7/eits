# IAM Builtin: block_interpreter_file_write

## Problem

An agent used Bash to invoke a scripting interpreter with inline code that wrote/edited
a file directly (e.g. `python3 -c "open('x.py','w').write(...)"`), bypassing the
Edit/Write tools. This is undesirable: file edits should go through the tracked
Edit/Write tool path, not opaque inline scripts.

This is scoped narrowly to the pattern actually observed — an interpreter's inline-code
flag (`-c`, `-e`, `--eval`, `-r`) used to write a file. It is **not** a general
"block scripts" or "block Bash" policy, and it does **not** target redirects
(`>`, `>>`), `tee`, `sed -i`, heredocs, `dd`, or base64 pipelines — those are common for
legitimate things (build logs, `mix format --check-formatted > file`, etc.) and blocking
them would create false positives disproportionate to the problem being solved.

## Approach

Follow the existing builtin-matcher pattern used throughout `lib/eye_in_the_sky/iam/builtin/`
(e.g. `block_sudo.ex`): a deterministic Elixir regex matcher, no LLM call, fast and
testable. This keeps the new policy consistent with every other builtin in the registry
rather than introducing a second enforcement style (LLM-judgment PreToolUse hook).

## Detection logic

New module: `EyeInTheSky.IAM.Builtin.BlockInterpreterFileWrite`

Matching is a two-step extract-then-search, **not** two independent regexes against the
whole command — checking write-indicators against the raw command string would
false-positive on unrelated juxtaposition, e.g.
`node -e "console.log(1)" && grep -n "open('w')" legacy.py` (interpreter flag and write
token both present, but unrelated to each other). To avoid this:

1. **Extract**: find an interpreter inline-code invocation and capture *only* the
   argument string passed to its flag:
   - `python` / `python3` (case-insensitive) with `-c <arg>`
   - `node` (case-insensitive) with `-e <arg>` or `--eval <arg>`/`--eval=<arg>`
   - `perl` with `-e <arg>`
   - `ruby` with `-e <arg>`
   - `php` with `-r <arg>`

   For v1, the inline-code flag must appear **immediately after the interpreter
   command**, allowing only whitespace between them (strict adjacency, not "any
   interpreter option before it"). `python3 -I -c "..."` or `python3 -u -c "..."` are
   **not** matched in v1 — those are legitimate interpreter options preceding `-c`, and
   supporting an open-ended options list risks mistaking a script's own positional
   argument for the inline-code flag. `python3 script.py -c foo` must not match either,
   since `-c` there is a script argument, not the interpreter's inline-code flag.
   Regex is case-insensitive (`/i`), mirroring `block_sudo.ex:17`.

   The extractor is a **heuristic regex matcher, not a full shell parser**. It supports
   common quoted and unquoted inline-code forms agents actually use in practice, but it
   is not expected to perfectly handle arbitrary Bash syntax, nested quoting, command
   substitution, or all escaped-quote edge cases.

2. **Search scoped substring only**: within the *captured argument* (not the full
   command), apply write indicators appropriate to the detected interpreter. A write
   mode is any mode string whose first character is `w`, `a`, or `x` — this covers
   `w`, `a`, `x`, `wb`, `ab`, `xb`, `w+`, `a+`, `x+`, `w+b`, `a+b`, etc., not just the
   exact strings `w`/`a`.

   - **Python**:
     - `open(` ... followed by a write-mode argument (`open(...'r')` read-mode must
       NOT match)
     - `pathlib.Path(...).write_text(`
     - `pathlib.Path(...).write_bytes(`
   - **Node**:
     - `writeFileSync(`
     - `writeFile(`
     - `fs.promises.writeFile(`
     - `require("fs")` / `require("node:fs")` chained into `writeFile*`
   - **Ruby**:
     - `File.write(`
     - `File.open(...)` with a write-mode argument
   - **PHP**:
     - `file_put_contents(`
     - `fopen(...)` with a write-mode argument
   - **Perl**:
     - `open` using `>` or `>>` mode

   Generic `.write(` and bare `fs.write` are **not** used as standalone indicators —
   they overmatch non-file targets (`sys.stdout.write(...)`, `process.stdout.write(...)`,
   `io.StringIO().write(...)`, raw fd writes). `.write(` only counts when it's chained
   directly off a file-open construct covered above (e.g. `open(...'w').write(...)`,
   `File.open(...'w') { |f| f.write(...) }`).

Both steps must succeed against the *same* extracted argument — `python3 -c "print(1+1)"`
or `node -e "console.log('hi')"` do not match (no write indicator inside the argument);
a command with a write indicator elsewhere in the line but not inside the flag's
argument (the `grep`/`node -e` juxtaposition example above) does not match either.

This is a substring/pattern heuristic, not a string-literal-aware parser: a decoy like
`node -e "console.log('writeFileSync(')"` (the indicator text appears only inside a
string being printed, not an actual write call) is expected to still match, since the
matcher cannot distinguish real code from string literals without a real JS parser.
This tradeoff is accepted and must be covered by an explicit test so it's a documented
decision, not a silent surprise.

If a command contains multiple inline-code invocations (e.g. piped:
`python3 -c "x" | python3 -c "y"`), each captured argument is checked independently;
the policy matches if any one of them contains a write indicator.

Supports the same `"allowPatterns"` condition escape hatch as `block_sudo` — a list of
regex strings matched against the full command; a match on any allowPattern makes the
policy not fire, for legitimate one-off exceptions an operator wants to permit.

## Files touched

- `lib/eye_in_the_sky/iam/builtin/block_interpreter_file_write.ex` — new matcher module,
  implementing `EyeInTheSky.IAM.BuiltinMatcher` behaviour (mirrors `block_sudo.ex`
  structure: `matches?/2`, private `allowed?/2` for the escape hatch).
- `lib/eye_in_the_sky/iam/builtin_matcher/registry.ex` — add
  `"block_interpreter_file_write" => Builtin.BlockInterpreterFileWrite` to `@matchers`.
- `lib/eye_in_the_sky/iam/seeds.ex` — add a system policy row:
  ```elixir
  %{
    system_key: "block_interpreter_file_write",
    name: "Block interpreter inline-code file writes",
    effect: "deny",
    action: "Bash",
    builtin_matcher: "block_interpreter_file_write",
    priority: 90,
    enabled: false,
    message: "Writing/editing files via interpreter inline code (python -c, node -e, etc.) is blocked. Use the Edit/Write tool instead."
  }
  ```
  Priority 90 (workflow-discipline tier, alongside `block_secrets_write` at 95) rather
  than 100 — this is not a security-critical block like `sudo`/`rm -rf`. Seeded
  **disabled** by default, matching precedent for other heuristic-risk builtins
  (`block_kubectl`, `block_terraform`): this is a new regex heuristic, not a
  well-established pattern, so operators opt in per-project/agent-type from the
  Policies UI rather than it firing unreviewed everywhere. `editable_fields` defaults
  per the existing seed helper (`enabled priority condition message`).
- `test/eye_in_the_sky/iam/builtin/block_interpreter_file_write_test.exs` — new test file,
  mirroring `block_sudo_test.exs`:

  Should match:
  - `python3 -c "open('f.py','w').write('x')"`
  - `python3 -c "open('f.bin','wb').write(b'x')"` (non-text write mode)
  - `python3 -c "open('f.txt','a+').write('x')"` (append+ mode)
  - `python3 -c "open('f.txt','x').write('x')"` (exclusive-create mode)
  - `python3 -c "from pathlib import Path; Path('f.txt').write_text('x')"`
  - `node -e "require('fs').writeFileSync('f.js','x')"`
  - `node -e "require('node:fs').writeFileSync('f.js','x')"`
  - `node -e "require('fs').promises.writeFile('f.js','x')"`
  - `node --eval "..."` and `node --eval=...` variants
  - `php -r "file_put_contents('f.php', 'x');"`
  - `ruby -e "File.open('f.txt', 'wb') { |f| f.write('x') }"`
  - `perl -e 'open(my $fh, ">", "x.txt"); print $fh "hi";'`
  - matches case-insensitive executable name (`PYTHON3 -c ...`)
  - matches mixed quoting (`python3 -c 'open("f","w").write("x")'`)
  - matches pipelined interpreters (`python3 -c "x" | python3 -c "y"` where only the
    second contains a write) — the policy fires because at least one segment matches
  - documented decoy: `node -e "console.log('writeFileSync(')"` — matches even though
    the indicator only appears inside a printed string literal (accepted false-positive
    tradeoff, see Detection logic)

  Should not match:
  - `python3 -c "print(1)"` (no write call)
  - `python3 -c "sys.stdout.write('not a file write')"` (non-file `.write(`)
  - `python3 -c "io.StringIO().write('x')"` (non-file `.write(`)
  - `node -e "process.stdout.write('hi')"` (non-file write)
  - `python3 -c "open('f','r').read()"` (read-mode, not write-mode)
  - cross-contamination: interpreter flag and write-token present but unrelated
    (`node -e "console.log(1)" && grep -n "open('w')" legacy.py`)
  - flag-position variance where `-c` is not the inline-code flag
    (`python3 script.py -c foo`)
  - interpreter option before the inline-code flag, out of v1 scope
    (`python3 -I -c "open('x','w').write('y')"`)
  - plain redirects (`echo hi > out.txt`)
  - reading files via cat/less/grep
  - `allowPatterns` escapes the match
  - ignores non-Bash tools

## Out of scope

- General shell redirects, `tee`, `sed -i`, `awk` in-place, `dd`, heredocs, base64-decode
  pipelines — explicitly excluded per the "narrow, observed pattern only" decision above.
- Full Bash lockout for any agent type — not requested; agents keep normal Bash access
  for builds/tests/git/etc.
- Static analysis/parsing of the inline code (e.g. an actual Python AST) — regex heuristic
  only, matching the precedent set by every other builtin matcher in this codebase.
