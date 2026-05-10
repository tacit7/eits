defmodule EyeInTheSkyWeb.Api.V1.TagControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.TaskTags

  defp create_tag!(name) do
    {:ok, tag} = TaskTags.get_or_create_tag(name)
    tag
  end

  describe "GET /api/v1/tags" do
    test "returns success with empty list when no tags exist", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/tags")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert is_list(resp["tags"])
    end

    test "returns all tags with id and name fields", %{conn: conn} do
      n = System.unique_integer([:positive])
      t1 = create_tag!("alpha-#{n}")
      t2 = create_tag!("beta-#{n}")

      conn = get(conn, ~p"/api/v1/tags")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      tags = resp["tags"]

      ids = Enum.map(tags, & &1["id"])
      assert t1.id in ids
      assert t2.id in ids

      tag_map = Enum.find(tags, &(&1["id"] == t1.id))
      assert tag_map["name"] == t1.name
      # Only id and name keys are exposed (not color or other fields)
      assert Map.keys(tag_map) |> Enum.sort() == ["id", "name"]
    end

    test "returns tags ordered by name ascending", %{conn: conn} do
      n = System.unique_integer([:positive])
      _c = create_tag!("zzz-ord-#{n}")
      _b = create_tag!("mmm-ord-#{n}")
      _a = create_tag!("aaa-ord-#{n}")

      conn = get(conn, ~p"/api/v1/tags")
      resp = json_response(conn, 200)

      our_names =
        resp["tags"]
        |> Enum.map(& &1["name"])
        |> Enum.filter(&String.ends_with?(&1, "-ord-#{n}"))

      assert our_names == ["aaa-ord-#{n}", "mmm-ord-#{n}", "zzz-ord-#{n}"]
    end

    test "filters tags by case-insensitive substring search via q param", %{conn: conn} do
      n = System.unique_integer([:positive])
      hit1 = create_tag!("Frontend-#{n}")
      hit2 = create_tag!("backend-frontend-#{n}")
      miss = create_tag!("database-#{n}")

      conn = get(conn, ~p"/api/v1/tags?q=front")
      resp = json_response(conn, 200)

      ids = Enum.map(resp["tags"], & &1["id"])
      assert hit1.id in ids
      assert hit2.id in ids
      refute miss.id in ids
    end

    test "case-insensitive search matches uppercase query against lowercase names", %{conn: conn} do
      n = System.unique_integer([:positive])
      tag = create_tag!("lowercase-tag-#{n}")

      conn = get(conn, ~p"/api/v1/tags?q=LOWERCASE")
      resp = json_response(conn, 200)

      ids = Enum.map(resp["tags"], & &1["id"])
      assert tag.id in ids
    end

    test "empty q param is treated as no filter", %{conn: conn} do
      n = System.unique_integer([:positive])
      tag = create_tag!("no-filter-#{n}")

      conn = get(conn, ~p"/api/v1/tags?q=")
      resp = json_response(conn, 200)

      ids = Enum.map(resp["tags"], & &1["id"])
      assert tag.id in ids
    end

    test "search with no matches returns empty list with success: true", %{conn: conn} do
      _ = create_tag!("real-tag-#{System.unique_integer([:positive])}")

      conn = get(conn, ~p"/api/v1/tags?q=zzz-no-such-tag-zzz-#{System.unique_integer([:positive])}")
      resp = json_response(conn, 200)

      assert resp["success"] == true
      assert resp["tags"] == []
    end
  end
end
