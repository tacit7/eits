defmodule EyeInTheSky.PiTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Pi

  setup do
    original = Application.get_env(:eye_in_the_sky, :pi_session_root)
    on_exit(fn ->
      System.delete_env("EITS_PI_SESSION_ROOT")
      if original,
        do: Application.put_env(:eye_in_the_sky, :pi_session_root, original),
        else: Application.delete_env(:eye_in_the_sky, :pi_session_root)
    end)
    :ok
  end

  test "env var wins over app config and default" do
    System.put_env("EITS_PI_SESSION_ROOT", "/tmp/pi-env-root")
    Application.put_env(:eye_in_the_sky, :pi_session_root, "/tmp/pi-cfg-root")
    assert Pi.session_root() == "/tmp/pi-env-root"
  end

  test "app config wins over default" do
    System.delete_env("EITS_PI_SESSION_ROOT")
    Application.put_env(:eye_in_the_sky, :pi_session_root, "/tmp/pi-cfg-root")
    assert Pi.session_root() == "/tmp/pi-cfg-root"
  end

  test "defaults to var/pi-sessions" do
    System.delete_env("EITS_PI_SESSION_ROOT")
    Application.delete_env(:eye_in_the_sky, :pi_session_root)
    assert Pi.session_root() == Path.expand("var/pi-sessions")
  end

  test "session_dir builds and creates the per-session directory" do
    tmp = Path.join(System.tmp_dir!(), "pi-root-#{System.unique_integer([:positive])}")
    System.put_env("EITS_PI_SESSION_ROOT", tmp)
    dir = Pi.session_dir("abc-123")
    assert dir == Path.join(tmp, "abc-123")
    assert File.dir?(dir)
  end
end
