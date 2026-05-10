defmodule EyeInTheSky.Diff.ParserTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Diff.Parser

  # ---------------------------------------------------------------------------
  # parse/2 — binary diff
  # ---------------------------------------------------------------------------

  describe "parse/2 — binary diff" do
    test "returns is_binary: true when raw contains Binary files ... differ" do
      raw = "Binary files a/image.png and b/image.png differ"
      result = Parser.parse(raw, "image.png")
      assert result == %{path: "image.png", hunks: [], is_binary: true}
    end

    test "uses provided path" do
      raw = "Binary files a/x and b/x differ"
      assert Parser.parse(raw, "x").path == "x"
    end
  end

  # ---------------------------------------------------------------------------
  # parse/2 — empty / no-hunk input
  # ---------------------------------------------------------------------------

  describe "parse/2 — empty input" do
    test "returns empty hunks for empty string" do
      result = Parser.parse("")
      assert result.hunks == []
      assert result.is_binary == false
    end

    test "default path is empty string" do
      result = Parser.parse("")
      assert result.path == ""
    end

    test "skips metadata-only diff (no @@ header)" do
      raw = """
      diff --git a/foo.ex b/foo.ex
      index abc..def 100644
      --- a/foo.ex
      +++ b/foo.ex
      """

      result = Parser.parse(raw, "foo.ex")
      assert result.hunks == []
    end
  end

  # ---------------------------------------------------------------------------
  # parse/2 — skip prefixes
  # ---------------------------------------------------------------------------

  describe "parse/2 — skipped header lines" do
    test "skips diff --git line" do
      raw = "diff --git a/foo b/foo\n@@ -1,1 +1,1 @@\n foo"
      result = Parser.parse(raw, "foo")
      assert length(result.hunks) == 1
    end

    test "skips new file mode line" do
      raw = "new file mode 100644\n@@ -0,0 +1,1 @@\n+line"
      result = Parser.parse(raw, "foo")
      assert length(result.hunks) == 1
    end

    test "skips deleted file mode line" do
      raw = "deleted file mode 100644\n@@ -1,1 +0,0 @@\n-line"
      result = Parser.parse(raw, "foo")
      assert length(result.hunks) == 1
    end

    test "skips similarity index line" do
      raw = "similarity index 95%\n@@ -1,1 +1,1 @@\n foo"
      result = Parser.parse(raw, "foo")
      assert length(result.hunks) == 1
    end

    test "skips rename from / rename to lines" do
      raw = "rename from old.ex\nrename to new.ex\n@@ -1,1 +1,1 @@\n foo"
      result = Parser.parse(raw, "new.ex")
      assert length(result.hunks) == 1
    end

    test "skips \\ No newline at end of file marker" do
      raw = "@@ -1,1 +1,1 @@\n-old\n+new\n\\ No newline at end of file"
      result = Parser.parse(raw)
      hunk = hd(result.hunks)
      types = Enum.map(hunk.lines, & &1.type)
      assert types == [:removed, :added]
    end

    test "skips old mode line" do
      raw = "old mode 100755\n@@ -1,1 +1,1 @@\n foo"
      result = Parser.parse(raw, "foo")
      assert length(result.hunks) == 1
    end

    test "skips new mode line" do
      raw = "new mode 100644\n@@ -1,1 +1,1 @@\n foo"
      result = Parser.parse(raw, "foo")
      assert length(result.hunks) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # parse/2 — single hunk
  # ---------------------------------------------------------------------------

  describe "parse/2 — single hunk" do
    test "parses hunk header and line numbers" do
      raw = "@@ -10,3 +10,3 @@\n foo\n-bar\n+baz"
      result = Parser.parse(raw, "file.ex")

      assert length(result.hunks) == 1
      [hunk] = result.hunks
      assert String.starts_with?(hunk.header, "@@")
    end

    test "added line has correct type, content, and new_line_number" do
      raw = "@@ -1,1 +1,2 @@\n ctx\n+added line"
      result = Parser.parse(raw)
      [hunk] = result.hunks

      added = Enum.find(hunk.lines, &(&1.type == :added))
      assert added.content == "added line"
      assert added.old_line_number == nil
      assert is_integer(added.new_line_number)
    end

    test "removed line has correct type, content, and old_line_number" do
      raw = "@@ -5,1 +5,0 @@\n-removed line"
      result = Parser.parse(raw)
      [hunk] = result.hunks

      removed = Enum.find(hunk.lines, &(&1.type == :removed))
      assert removed.content == "removed line"
      assert removed.new_line_number == nil
      assert removed.old_line_number == 5
    end

    test "context line has both old and new line numbers" do
      raw = "@@ -3,1 +3,1 @@\n context line"
      result = Parser.parse(raw)
      [hunk] = result.hunks

      ctx = hd(hunk.lines)
      assert ctx.type == :context
      # parser strips the leading space sigil
      assert ctx.content == "context line"
      assert ctx.old_line_number == 3
      assert ctx.new_line_number == 3
    end

    test "line numbers increment correctly across context lines" do
      raw = "@@ -1,3 +1,3 @@\n line1\n line2\n line3"
      result = Parser.parse(raw)
      [hunk] = result.hunks

      [l1, l2, l3] = hunk.lines
      assert l1.old_line_number == 1
      assert l2.old_line_number == 2
      assert l3.old_line_number == 3
      assert l1.new_line_number == 1
      assert l2.new_line_number == 2
      assert l3.new_line_number == 3
    end

    test "added lines advance new_line_number only" do
      raw = "@@ -1,1 +1,3 @@\n ctx\n+add1\n+add2"
      result = Parser.parse(raw)
      [hunk] = result.hunks

      added = Enum.filter(hunk.lines, &(&1.type == :added))
      [a1, a2] = added
      assert a1.new_line_number == 2
      assert a2.new_line_number == 3
    end

    test "removed lines advance old_line_number only" do
      raw = "@@ -1,3 +1,1 @@\n ctx\n-rem1\n-rem2"
      result = Parser.parse(raw)
      [hunk] = result.hunks

      removed = Enum.filter(hunk.lines, &(&1.type == :removed))
      [r1, r2] = removed
      assert r1.old_line_number == 2
      assert r2.old_line_number == 3
    end

    test "strips leading +/-/space sigil from content" do
      raw = "@@ -1,1 +1,1 @@\n+the added content"
      result = Parser.parse(raw)
      [hunk] = result.hunks
      added = hd(hunk.lines)
      assert added.content == "the added content"
    end
  end

  # ---------------------------------------------------------------------------
  # parse/2 — multiple hunks
  # ---------------------------------------------------------------------------

  describe "parse/2 — multiple hunks" do
    test "creates one hunk per @@ header" do
      raw = """
      @@ -1,1 +1,1 @@
       ctx1
      @@ -10,1 +10,1 @@
       ctx2
      """

      result = Parser.parse(raw)
      assert length(result.hunks) == 2
    end

    test "each hunk contains only its own lines" do
      raw = "@@ -1,1 +1,1 @@\n ctx1\n@@ -10,1 +10,1 @@\n ctx2"
      result = Parser.parse(raw)
      [h1, h2] = result.hunks

      assert length(h1.lines) == 1
      assert hd(h1.lines).content == "ctx1"
      assert length(h2.lines) == 1
      assert hd(h2.lines).content == "ctx2"
    end

    test "hunk header stored verbatim on each hunk" do
      raw = "@@ -5,3 +5,3 @@\n ctx\n@@ -20,2 +20,2 @@\n ctx"
      result = Parser.parse(raw)
      [h1, h2] = result.hunks
      assert String.contains?(h1.header, "-5,3")
      assert String.contains?(h2.header, "-20,2")
    end
  end

  # ---------------------------------------------------------------------------
  # parse/2 — hunk header without optional comma counts
  # ---------------------------------------------------------------------------

  describe "parse/2 — hunk header without count" do
    test "handles @@ -1 +1 @@ (no comma form)" do
      raw = "@@ -1 +1 @@\n ctx"
      result = Parser.parse(raw)
      assert length(result.hunks) == 1
      [hunk] = result.hunks
      ctx = hd(hunk.lines)
      assert ctx.old_line_number == 1
      assert ctx.new_line_number == 1
    end
  end

  # ---------------------------------------------------------------------------
  # parse/2 — malformed hunk header fallback
  # ---------------------------------------------------------------------------

  describe "parse/2 — malformed @@ header" do
    test "falls back to line numbers starting at 1" do
      raw = "@@ garbled header @@\n ctx"
      result = Parser.parse(raw)
      assert length(result.hunks) == 1
      [hunk] = result.hunks
      ctx = hd(hunk.lines)
      assert ctx.old_line_number == 1
      assert ctx.new_line_number == 1
    end
  end

  # ---------------------------------------------------------------------------
  # parse/2 — CRLF line endings
  # ---------------------------------------------------------------------------

  describe "parse/2 — CRLF line endings" do
    test "strips carriage returns from lines" do
      raw = "@@ -1,1 +1,1 @@\r\n ctx\r\n"
      result = Parser.parse(raw)
      [hunk] = result.hunks
      # parser strips leading space sigil
      assert hd(hunk.lines).content == "ctx"
    end
  end

  # ---------------------------------------------------------------------------
  # pair_lines/1
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # parse/2 — unrecognized line sigil inside a hunk (true -> fallback)
  # ---------------------------------------------------------------------------

  describe "parse/2 — unrecognized sigil inside hunk" do
    test "empty string line inside hunk is silently skipped" do
      raw = "@@ -1,2 +1,2 @@\n foo\n\n bar"
      result = Parser.parse(raw)
      [hunk] = result.hunks
      # only the two space-prefixed context lines should appear
      assert length(hunk.lines) == 2
      types = Enum.map(hunk.lines, & &1.type)
      assert types == [:context, :context]
    end
  end

  # ---------------------------------------------------------------------------
  # pair_lines/1
  # ---------------------------------------------------------------------------

  describe "pair_lines/1 — empty" do
    test "returns empty list for empty input" do
      assert Parser.pair_lines([]) == []
    end
  end

  describe "pair_lines/1 — context lines" do
    test "pairs context line with itself on both sides" do
      ctx = %{type: :context, content: "foo", old_line_number: 1, new_line_number: 1}
      [{left, right}] = Parser.pair_lines([ctx])
      assert left == ctx
      assert right == ctx
    end
  end

  describe "pair_lines/1 — added-only lines" do
    test "added with no preceding removed becomes {nil, line}" do
      added = %{type: :added, content: "new", old_line_number: nil, new_line_number: 1}
      [{left, right}] = Parser.pair_lines([added])
      assert left == nil
      assert right == added
    end

    test "multiple adds without removes all get nil left" do
      a1 = %{type: :added, content: "a1", old_line_number: nil, new_line_number: 1}
      a2 = %{type: :added, content: "a2", old_line_number: nil, new_line_number: 2}
      rows = Parser.pair_lines([a1, a2])
      assert rows == [{nil, a1}, {nil, a2}]
    end
  end

  describe "pair_lines/1 — removed-only lines" do
    test "removed with no following added becomes {line, nil} at end" do
      removed = %{type: :removed, content: "old", old_line_number: 1, new_line_number: nil}
      [{left, right}] = Parser.pair_lines([removed])
      assert left == removed
      assert right == nil
    end

    test "multiple removes without adds all get nil right" do
      r1 = %{type: :removed, content: "r1", old_line_number: 1, new_line_number: nil}
      r2 = %{type: :removed, content: "r2", old_line_number: 2, new_line_number: nil}
      rows = Parser.pair_lines([r1, r2])
      assert rows == [{r1, nil}, {r2, nil}]
    end
  end

  describe "pair_lines/1 — remove then add (paired)" do
    test "remove followed by add becomes a paired row" do
      removed = %{type: :removed, content: "old", old_line_number: 1, new_line_number: nil}
      added = %{type: :added, content: "new", old_line_number: nil, new_line_number: 1}
      rows = Parser.pair_lines([removed, added])
      assert rows == [{removed, added}]
    end

    test "two removes then two adds pairs them 1-to-1" do
      r1 = %{type: :removed, content: "r1", old_line_number: 1, new_line_number: nil}
      r2 = %{type: :removed, content: "r2", old_line_number: 2, new_line_number: nil}
      a1 = %{type: :added, content: "a1", old_line_number: nil, new_line_number: 1}
      a2 = %{type: :added, content: "a2", old_line_number: nil, new_line_number: 2}
      rows = Parser.pair_lines([r1, r2, a1, a2])
      assert rows == [{r1, a1}, {r2, a2}]
    end
  end

  describe "pair_lines/1 — context flushes remove buffer" do
    test "buffered remove is flushed as {remove, nil} before context pair" do
      removed = %{type: :removed, content: "old", old_line_number: 1, new_line_number: nil}
      ctx = %{type: :context, content: "ctx", old_line_number: 2, new_line_number: 2}
      rows = Parser.pair_lines([removed, ctx])
      assert rows == [{removed, nil}, {ctx, ctx}]
    end
  end

  describe "pair_lines/1 — more adds than removes" do
    test "extra adds after removes become {nil, add}" do
      r1 = %{type: :removed, content: "r1", old_line_number: 1, new_line_number: nil}
      a1 = %{type: :added, content: "a1", old_line_number: nil, new_line_number: 1}
      a2 = %{type: :added, content: "a2", old_line_number: nil, new_line_number: 2}
      rows = Parser.pair_lines([r1, a1, a2])
      assert rows == [{r1, a1}, {nil, a2}]
    end
  end

  describe "pair_lines/1 — more removes than adds" do
    test "extra removes after adds exhaust buffer and become {remove, nil}" do
      r1 = %{type: :removed, content: "r1", old_line_number: 1, new_line_number: nil}
      r2 = %{type: :removed, content: "r2", old_line_number: 2, new_line_number: nil}
      a1 = %{type: :added, content: "a1", old_line_number: nil, new_line_number: 1}
      rows = Parser.pair_lines([r1, r2, a1])
      assert rows == [{r1, a1}, {r2, nil}]
    end
  end

  describe "pair_lines/1 — integration with parse/2 output" do
    test "pairs lines from a real-ish diff hunk" do
      raw = "@@ -1,2 +1,2 @@\n ctx\n-old\n+new"
      result = Parser.parse(raw)
      [hunk] = result.hunks
      rows = Parser.pair_lines(hunk.lines)

      # Context pairs with itself, removed+added are paired together
      assert length(rows) == 2
      [{ctx_l, ctx_r}, {rem, add}] = rows
      assert ctx_l.type == :context
      assert ctx_r.type == :context
      assert rem.type == :removed
      assert add.type == :added
    end
  end
end
