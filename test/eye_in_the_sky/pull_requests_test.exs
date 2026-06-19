defmodule EyeInTheSky.PullRequestsTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.PullRequests
  alias EyeInTheSky.PullRequests.PullRequest
  import EyeInTheSky.Factory

  defp pr_attrs(session, overrides \\ %{}) do
    Map.merge(
      %{
        session_id: session.id,
        pr_number: System.unique_integer([:positive]),
        pr_url: "https://github.com/example/repo/pull/1",
        base_branch: "main",
        head_branch: "feature-#{uniq()}"
      },
      overrides
    )
  end

  defp create_pr!(session, overrides \\ %{}) do
    {:ok, pr} = PullRequests.create_pr(pr_attrs(session, overrides))
    pr
  end

  describe "create_pr/1" do
    test "creates a PR with valid attrs" do
      session = new_session()
      attrs = pr_attrs(session)

      assert {:ok, %PullRequest{} = pr} = PullRequests.create_pr(attrs)
      assert pr.session_id == session.id
      assert pr.pr_number == attrs.pr_number
      assert pr.pr_url == attrs.pr_url
      assert pr.base_branch == "main"
      assert pr.head_branch == attrs.head_branch
      assert %DateTime{} = pr.created_at
    end

    test "requires session_id" do
      assert {:error, changeset} = PullRequests.create_pr(%{pr_number: 1})
      assert %{session_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects non-positive pr_number" do
      session = new_session()
      assert {:error, changeset} = PullRequests.create_pr(pr_attrs(session, %{pr_number: 0}))
      assert "must be greater than 0" in errors_on(changeset).pr_number
    end

    test "rejects negative pr_number" do
      session = new_session()
      assert {:error, changeset} = PullRequests.create_pr(pr_attrs(session, %{pr_number: -5}))
      assert "must be greater than 0" in errors_on(changeset).pr_number
    end

    test "rejects malformed pr_url" do
      session = new_session()

      assert {:error, changeset} =
               PullRequests.create_pr(pr_attrs(session, %{pr_url: "not-a-url"}))

      assert "must be a valid URL" in errors_on(changeset).pr_url
    end

    test "accepts http and https pr_url" do
      session = new_session()

      assert {:ok, _} =
               PullRequests.create_pr(pr_attrs(session, %{pr_url: "http://example.com/pr/1"}))

      assert {:ok, _} =
               PullRequests.create_pr(pr_attrs(session, %{pr_url: "https://example.com/pr/2"}))
    end

    test "allows nil optional fields" do
      session = new_session()

      assert {:ok, pr} =
               PullRequests.create_pr(%{
                 session_id: session.id
               })

      assert pr.pr_number == nil
      assert pr.pr_url == nil
      assert pr.base_branch == nil
      assert pr.head_branch == nil
    end

    test "uses default empty attrs" do
      assert {:error, changeset} = PullRequests.create_pr()
      assert %{session_id: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "get_pr!/1" do
    test "returns the PR with the given id" do
      session = new_session()
      pr = create_pr!(session)
      fetched = PullRequests.get_pr!(pr.id)
      assert fetched.id == pr.id
      assert fetched.session_id == session.id
    end

    test "raises Ecto.NoResultsError for missing id" do
      assert_raise Ecto.NoResultsError, fn -> PullRequests.get_pr!(-1) end
    end
  end

  describe "list_prs_for_session/2" do
    test "returns empty list when session has no PRs" do
      session = new_session()
      assert PullRequests.list_prs_for_session(session.id) == []
    end

    test "returns only PRs for the given session" do
      session_a = new_session()
      session_b = new_session()
      pr_a = create_pr!(session_a)
      _pr_b = create_pr!(session_b)

      results = PullRequests.list_prs_for_session(session_a.id)
      assert length(results) == 1
      assert hd(results).id == pr_a.id
    end

    test "orders by created_at desc" do
      session = new_session()
      pr1 = create_pr!(session)
      # ensure distinct created_at — :utc_datetime resolves to seconds
      :timer.sleep(1100)
      pr2 = create_pr!(session)

      [first, second] = PullRequests.list_prs_for_session(session.id)
      assert first.id == pr2.id
      assert second.id == pr1.id
    end

    test "respects custom limit" do
      session = new_session()
      Enum.each(1..3, fn _ -> create_pr!(session) end)

      assert length(PullRequests.list_prs_for_session(session.id, limit: 2)) == 2
      assert length(PullRequests.list_prs_for_session(session.id, limit: 10)) == 3
    end

    test "default limit is 200 (returns all when fewer)" do
      session = new_session()
      Enum.each(1..3, fn _ -> create_pr!(session) end)
      assert length(PullRequests.list_prs_for_session(session.id)) == 3
    end
  end

  describe "update_pr/2" do
    test "updates fields with valid attrs" do
      session = new_session()
      pr = create_pr!(session)

      assert {:ok, updated} =
               PullRequests.update_pr(pr, %{
                 pr_url: "https://example.com/pr/updated",
                 base_branch: "develop"
               })

      assert updated.id == pr.id
      assert updated.pr_url == "https://example.com/pr/updated"
      assert updated.base_branch == "develop"
    end

    test "returns error changeset for invalid attrs" do
      session = new_session()
      pr = create_pr!(session)

      assert {:error, changeset} = PullRequests.update_pr(pr, %{pr_number: 0})
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).pr_number
    end

    test "rejects invalid url on update" do
      session = new_session()
      pr = create_pr!(session)

      assert {:error, changeset} = PullRequests.update_pr(pr, %{pr_url: "ftp://nope"})
      assert "must be a valid URL" in errors_on(changeset).pr_url
    end
  end

  describe "delete_pr/1" do
    test "deletes the PR" do
      session = new_session()
      pr = create_pr!(session)

      assert {:ok, deleted} = PullRequests.delete_pr(pr)
      assert deleted.id == pr.id
      assert_raise Ecto.NoResultsError, fn -> PullRequests.get_pr!(pr.id) end
    end
  end

  describe "change_pr/2" do
    test "returns a changeset" do
      session = new_session()
      pr = create_pr!(session)

      assert %Ecto.Changeset{} = changeset = PullRequests.change_pr(pr)
      assert changeset.valid?
    end

    test "applies attrs to the changeset" do
      session = new_session()
      pr = create_pr!(session)

      changeset = PullRequests.change_pr(pr, %{base_branch: "develop"})
      assert changeset.changes.base_branch == "develop"
    end

    test "surfaces validation errors via change_pr" do
      session = new_session()
      pr = create_pr!(session)

      changeset = PullRequests.change_pr(pr, %{pr_number: -1})
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).pr_number
    end

    test "default empty attrs returns valid changeset" do
      pr = %PullRequest{session_id: 1, pr_number: 5}
      assert %Ecto.Changeset{} = PullRequests.change_pr(pr)
    end
  end
end
