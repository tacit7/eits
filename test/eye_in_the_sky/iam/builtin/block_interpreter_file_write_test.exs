defmodule EyeInTheSky.IAM.Builtin.BlockInterpreterFileWriteTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.BlockInterpreterFileWrite
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}
  defp policy(cond \\ %{}), do: %Policy{condition: cond}

  describe "matches" do
    test "python open write mode" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[python3 -c "open('f.py','w').write('x')"])
             )
    end

    test "python open binary write mode" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[python3 -c "open('f.bin','wb').write(b'x')"])
             )
    end

    test "python open append-plus mode" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[python3 -c "open('f.txt','a+').write('x')"])
             )
    end

    test "python open exclusive-create mode" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[python3 -c "open('f.txt','x').write('x')"])
             )
    end

    test "python pathlib write_text" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[python3 -c "from pathlib import Path; Path('f.txt').write_text('x')"])
             )
    end

    test "node writeFileSync via require('fs')" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[node -e "require('fs').writeFileSync('f.js','x')"])
             )
    end

    test "node writeFileSync via require('node:fs')" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[node -e "require('node:fs').writeFileSync('f.js','x')"])
             )
    end

    test "node fs.promises.writeFile" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[node -e "require('fs').promises.writeFile('f.js','x')"])
             )
    end

    test "node --eval with space" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[node --eval "require('fs').writeFileSync('f.js','x')"])
             )
    end

    test "node --eval= with equals" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[node --eval="require('fs').writeFileSync('f.js','x')"])
             )
    end

    test "php file_put_contents" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[php -r "file_put_contents('f.php', 'x');"])
             )
    end

    test "ruby File.open write mode" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[ruby -e "File.open('f.txt', 'wb') { |f| f.write('x') }"])
             )
    end

    test "perl open with > mode" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[perl -e 'open(my $fh, ">", "x.txt"); print $fh "hi";'])
             )
    end

    test "case-insensitive executable name" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[PYTHON3 -c "open('f.py','w').write('x')"])
             )
    end

    test "mixed quoting (single quote wrapping double-quoted python)" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[python3 -c 'open("f","w").write("x")'])
             )
    end

    test "pipelined interpreters, only the second writes" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[python3 -c "x" | python3 -c "open('f','w').write('y')"])
             )
    end

    test "documented decoy: write indicator only inside a printed string still matches" do
      assert BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[node -e "console.log('writeFileSync(')"])
             )
    end
  end

  describe "does not match" do
    test "python inline code with no write call" do
      refute BlockInterpreterFileWrite.matches?(policy(), ctx(~s[python3 -c "print(1)"]))
    end

    test "python non-file stdout write" do
      refute BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[python3 -c "sys.stdout.write('not a file write')"])
             )
    end

    test "python non-file StringIO write" do
      refute BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[python3 -c "io.StringIO().write('x')"])
             )
    end

    test "node non-file stdout write" do
      refute BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[node -e "process.stdout.write('hi')"])
             )
    end

    test "python read-mode open" do
      refute BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[python3 -c "open('f','r').read()"])
             )
    end

    test "cross-contamination: interpreter flag and write-token unrelated" do
      refute BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[node -e "console.log(1)" && grep -n "open('w')" legacy.py])
             )
    end

    test "flag-position variance: -c is a script argument, not the inline-code flag" do
      refute BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[python3 script.py -c "open('x','w').write('y')"])
             )
    end

    test "interpreter option before inline-code flag is out of v1 scope" do
      refute BlockInterpreterFileWrite.matches?(
               policy(),
               ctx(~s[python3 -I -c "open('x','w').write('y')"])
             )
    end

    test "plain redirect" do
      refute BlockInterpreterFileWrite.matches?(policy(), ctx("echo hi > out.txt"))
    end

    test "reading a file via cat" do
      refute BlockInterpreterFileWrite.matches?(policy(), ctx("cat script.py"))
    end

    test "allowPatterns can escape the match" do
      p = policy(%{"allowPatterns" => ["^python3 -c \"open\\('f.py'"]})

      refute BlockInterpreterFileWrite.matches?(
               p,
               ctx(~s[python3 -c "open('f.py','w').write('x')"])
             )
    end

    test "ignores non-Bash tools" do
      refute BlockInterpreterFileWrite.matches?(policy(), %Context{
               tool: "Read",
               resource_content: ~s[python3 -c "open('f.py','w').write('x')"]
             })
    end
  end
end
