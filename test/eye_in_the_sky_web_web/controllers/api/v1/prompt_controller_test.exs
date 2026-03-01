defmodule EyeInTheSkyWebWeb.Api.V1.PromptControllerTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  alias EyeInTheSkyWeb.Prompts

  defp uniq, do: System.unique_integer([:positive])

  defp valid_prompt_params(overrides \\ %{}) do
    n = uniq()

    Map.merge(
      %{
        "name" => "Test Prompt #{n}",
        "slug" => "test-prompt-#{n}",
        "prompt_text" => "You are a helpful assistant #{n}"
      },
      overrides
    )
  end

  # ---- POST /api/v1/prompts ----

  describe "POST /api/v1/prompts" do
    test "creates a prompt with valid params", %{conn: conn} do
      params = valid_prompt_params()

      conn = post(conn, ~p"/api/v1/prompts", params)
      resp = json_response(conn, 201)

      assert resp["name"] == params["name"]
      assert resp["slug"] == params["slug"]
      assert is_integer(resp["id"])
      assert is_binary(resp["uuid"])
      assert resp["version"] == 1
    end

    test "creates a prompt with optional fields", %{conn: conn} do
      params =
        valid_prompt_params(%{
          "description" => "A test description",
          "tags" => "test,prompt",
          "created_by" => "test-agent"
        })

      conn = post(conn, ~p"/api/v1/prompts", params)
      resp = json_response(conn, 201)

      assert resp["name"] == params["name"]
      assert resp["description"] == "A test description"
    end

    test "returns 422 when name is missing", %{conn: conn} do
      params = valid_prompt_params() |> Map.delete("name")

      conn = post(conn, ~p"/api/v1/prompts", params)
      resp = json_response(conn, 422)

      assert resp["error"] == "Failed to create prompt"
      assert resp["details"]["name"] != nil
    end

    test "returns 422 when slug is missing", %{conn: conn} do
      params = valid_prompt_params() |> Map.delete("slug")

      conn = post(conn, ~p"/api/v1/prompts", params)
      resp = json_response(conn, 422)

      assert resp["error"] == "Failed to create prompt"
      assert resp["details"]["slug"] != nil
    end

    test "returns 422 when prompt_text is missing", %{conn: conn} do
      params = valid_prompt_params() |> Map.delete("prompt_text")

      conn = post(conn, ~p"/api/v1/prompts", params)
      resp = json_response(conn, 422)

      assert resp["error"] == "Failed to create prompt"
      assert resp["details"]["prompt_text"] != nil
    end

    test "returns 422 for invalid slug format", %{conn: conn} do
      params = valid_prompt_params(%{"slug" => "Invalid Slug!"})

      conn = post(conn, ~p"/api/v1/prompts", params)
      resp = json_response(conn, 422)

      assert resp["error"] == "Failed to create prompt"
      assert resp["details"]["slug"] != nil
    end

    test "slug must be kebab-case", %{conn: conn} do
      params = valid_prompt_params(%{"slug" => "UPPERCASE"})

      conn = post(conn, ~p"/api/v1/prompts", params)
      assert json_response(conn, 422)["details"]["slug"] != nil
    end

    test "prompt is persisted and retrievable", %{conn: conn} do
      params = valid_prompt_params()

      conn = post(conn, ~p"/api/v1/prompts", params)
      resp = json_response(conn, 201)

      prompt = Prompts.get_prompt!(resp["id"])
      assert prompt.name == params["name"]
      assert prompt.slug == params["slug"]
      assert prompt.prompt_text == params["prompt_text"]
      assert prompt.active == true
    end

    test "auto-generates uuid and timestamps", %{conn: conn} do
      params = valid_prompt_params()

      conn = post(conn, ~p"/api/v1/prompts", params)
      resp = json_response(conn, 201)

      prompt = Prompts.get_prompt!(resp["id"])
      assert prompt.uuid != nil
      assert prompt.created_at != nil
      assert prompt.updated_at != nil
    end
  end
end
