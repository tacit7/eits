defmodule EyeInTheSkyWebWeb.Helpers.SlashItemsTest do
  use EyeInTheSkyWeb.DataCase, async: true

  alias EyeInTheSkyWebWeb.Helpers.SlashItems

  # --- extract_description ---

  describe "extract_description/1" do
    test "extracts description from YAML frontmatter" do
      content = """
      ---
      description: "Does something useful"
      ---
      # My Command
      Body text here.
      """

      assert SlashItems.extract_description(content) == "Does something useful"
    end

    test "falls back to first heading when no frontmatter" do
      content = """
      # My Skill Title
      Some body text.
      """

      assert SlashItems.extract_description(content) == "My Skill Title"
    end

    test "falls back to first heading when frontmatter has no description key" do
      content = """
      ---
      author: someone
      ---
      # Heading Here
      Body.
      """

      assert SlashItems.extract_description(content) == "Heading Here"
    end

    test "returns empty string when no heading and no frontmatter" do
      assert SlashItems.extract_description("just some plain text\nno heading") == ""
    end

    test "handles unquoted description in frontmatter" do
      content = """
      ---
      description: Unquoted description
      ---
      # Ignored
      """

      assert SlashItems.extract_description(content) == "Unquoted description"
    end
  end

  # --- load_skills/2 with temp dirs ---

  describe "load_skills/2" do
    setup do
      tmp = System.tmp_dir!()
      base = Path.join(tmp, "slash_test_#{System.unique_integer([:positive])}")
      cmds_dir = Path.join(base, "commands")
      skills_dir = Path.join(base, "skills")
      File.mkdir_p!(cmds_dir)
      File.mkdir_p!(skills_dir)
      on_exit(fn -> File.rm_rf!(base) end)
      %{cmds_dir: cmds_dir, skills_dir: skills_dir}
    end

    test "loads a direct .md command file", %{cmds_dir: cmds_dir, skills_dir: skills_dir} do
      File.write!(Path.join(cmds_dir, "my-cmd.md"), "# My Command\nDoes stuff.")

      items = SlashItems.load_skills(cmds_dir, skills_dir)

      assert Enum.any?(items, fn i -> i.slug == "my-cmd" and i.type == "command" end)
    end

    test "loads subdirectory commands with colon slug", %{
      cmds_dir: cmds_dir,
      skills_dir: skills_dir
    } do
      subdir = Path.join(cmds_dir, "sc")
      File.mkdir_p!(subdir)
      File.write!(Path.join(subdir, "build.md"), "# Build\nBuilds the project.")

      items = SlashItems.load_skills(cmds_dir, skills_dir)

      assert Enum.any?(items, fn i -> i.slug == "sc:build" and i.type == "command" end)
    end

    test "loads skills from SKILL.md", %{cmds_dir: cmds_dir, skills_dir: skills_dir} do
      skill_dir = Path.join(skills_dir, "eits-init")
      File.mkdir_p!(skill_dir)
      File.write!(Path.join(skill_dir, "SKILL.md"), "# EITS Init\nInitializes the session.")

      items = SlashItems.load_skills(cmds_dir, skills_dir)

      assert Enum.any?(items, fn i -> i.slug == "eits-init" and i.type == "skill" end)
    end

    test "skips skill dirs without SKILL.md", %{cmds_dir: cmds_dir, skills_dir: skills_dir} do
      orphan_dir = Path.join(skills_dir, "orphan")
      File.mkdir_p!(orphan_dir)
      File.write!(Path.join(orphan_dir, "README.md"), "# Not a skill")

      items = SlashItems.load_skills(cmds_dir, skills_dir)

      refute Enum.any?(items, fn i -> i.slug == "orphan" end)
    end

    test "returns empty list when commands dir does not exist", %{skills_dir: skills_dir} do
      items = SlashItems.load_skills("/nonexistent/commands", skills_dir)
      assert items == []
    end

    test "returns empty list when skills dir does not exist", %{cmds_dir: cmds_dir} do
      items = SlashItems.load_skills(cmds_dir, "/nonexistent/skills")
      assert items == []
    end

    test "description extracted from frontmatter for commands", %{
      cmds_dir: cmds_dir,
      skills_dir: skills_dir
    } do
      content = """
      ---
      description: "Runs the build pipeline"
      ---
      # Build
      """

      File.write!(Path.join(cmds_dir, "build.md"), content)

      items = SlashItems.load_skills(cmds_dir, skills_dir)
      item = Enum.find(items, &(&1.slug == "build"))
      assert item.description == "Runs the build pipeline"
    end
  end

  # --- load_prompts/0 ---

  describe "load_prompts/0" do
    test "includes prompts with valid slugs" do
      alias EyeInTheSkyWeb.Prompts

      {:ok, _} =
        Prompts.create_prompt(%{
          uuid: Ecto.UUID.generate(),
          name: "My Prompt",
          slug: "my-prompt",
          prompt_text: "Do something",
          active: true
        })

      items = SlashItems.load_prompts()

      assert Enum.any?(items, &(&1.slug == "my-prompt"))
    end

    test "all returned prompts have non-nil slugs" do
      items = SlashItems.load_prompts()
      assert Enum.all?(items, fn i -> not is_nil(i.slug) and i.slug != "" end)
    end

    test "all returned prompts have type 'prompt'" do
      alias EyeInTheSkyWeb.Prompts

      Prompts.create_prompt(%{
        uuid: Ecto.UUID.generate(),
        name: "Test",
        slug: "test-prompt-type",
        prompt_text: "x",
        active: true
      })

      items = SlashItems.load_prompts()
      assert Enum.all?(items, &(&1.type == "prompt"))
    end
  end

  # --- load_agents/0 ---

  describe "load_agents/0" do
    test "deduplicates agents by slug" do
      items = SlashItems.load_agents()
      slugs = Enum.map(items, & &1.slug)
      assert length(slugs) == length(Enum.uniq(slugs))
    end

    test "all agents have type 'agent'" do
      items = SlashItems.load_agents()
      assert Enum.all?(items, &(&1.type == "agent"))
    end

    test "slugs are capped at 60 characters" do
      items = SlashItems.load_agents()
      assert Enum.all?(items, fn i -> String.length(i.slug) <= 60 end)
    end
  end
end
