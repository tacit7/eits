defmodule ErroringAdapter do
  @moduledoc false
  # Minimal Plug adapter stub: only read_req_body is exercised by these tests.
  # Returns the reason from opts[:error] (default :timeout).
  def read_req_body(_state, opts) do
    {:error, Keyword.get(opts, :error, :timeout)}
  end
end

defmodule EyeInTheSkyWeb.Plugs.CaptureRawBodyTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias EyeInTheSkyWeb.Plugs.CaptureRawBody

  describe "read_body/2 — full body in one read ({:ok, ...})" do
    test "returns the body and assigns it to :raw_body" do
      body = ~s({"hello":"world"})

      conn =
        conn(:post, "/", body) |> Plug.Conn.put_req_header("content-type", "application/json")

      assert {:ok, ^body, conn} = CaptureRawBody.read_body(conn, [])
      assert conn.assigns[:raw_body] == body
    end

    test "appends to existing :raw_body when called multiple times" do
      conn =
        conn(:post, "/", "second")
        |> Plug.Conn.assign(:raw_body, "first-")

      assert {:ok, "second", conn} = CaptureRawBody.read_body(conn, [])
      assert conn.assigns[:raw_body] == "first-second"
    end

    test "handles empty body" do
      conn = conn(:post, "/", "")

      assert {:ok, "", conn} = CaptureRawBody.read_body(conn, [])
      assert conn.assigns[:raw_body] == ""
    end

    test "initializes :raw_body when not previously assigned" do
      conn = conn(:post, "/", "abc")
      refute Map.has_key?(conn.assigns, :raw_body)

      assert {:ok, "abc", conn} = CaptureRawBody.read_body(conn, [])
      assert conn.assigns[:raw_body] == "abc"
    end
  end

  describe "read_body/2 — chunked reads ({:more, ...})" do
    test "captures partial chunk and supports a follow-up read" do
      body = String.duplicate("x", 100)
      conn = conn(:post, "/", body)

      # First read with a small length forces {:more, chunk, conn}
      assert {:more, chunk1, conn} = CaptureRawBody.read_body(conn, length: 10, read_length: 10)
      assert byte_size(chunk1) > 0
      assert conn.assigns[:raw_body] == chunk1

      # Drain the rest via repeated calls; result may be :more or :ok depending on size.
      {final_conn, accumulated} = drain(conn, chunk1)
      assert accumulated == body
      assert final_conn.assigns[:raw_body] == body
    end

    test "appends chunk to pre-existing :raw_body" do
      body = String.duplicate("y", 50)

      conn =
        conn(:post, "/", body)
        |> Plug.Conn.assign(:raw_body, "prefix-")

      assert {:more, chunk, conn} = CaptureRawBody.read_body(conn, length: 5, read_length: 5)
      assert conn.assigns[:raw_body] == "prefix-" <> chunk
    end
  end

  describe "read_body/2 — error path ({:error, ...})" do
    test "passes through {:error, reason} from Plug.Conn.read_body without touching assigns" do
      conn = conn(:post, "/", "ignored")
      # Swap the test adapter for one whose read_req_body returns {:error, :timeout}.
      conn = %{conn | adapter: {ErroringAdapter, conn.adapter |> elem(1)}}

      assert {:error, :timeout} = CaptureRawBody.read_body(conn, [])
    end

    test "does not assign :raw_body on error" do
      conn =
        conn(:post, "/", "ignored")
        |> Plug.Conn.assign(:raw_body, "untouched")

      conn = %{conn | adapter: {ErroringAdapter, conn.adapter |> elem(1)}}

      assert {:error, :closed} = CaptureRawBody.read_body(conn, error: :closed)
      # The original assign is preserved because the conn is not threaded through.
      assert conn.assigns[:raw_body] == "untouched"
    end
  end

  # ---- helpers ----

  defp drain(conn, acc) do
    case CaptureRawBody.read_body(conn, length: 10, read_length: 10) do
      {:ok, chunk, conn} -> {conn, acc <> chunk}
      {:more, chunk, conn} -> drain(conn, acc <> chunk)
    end
  end
end
