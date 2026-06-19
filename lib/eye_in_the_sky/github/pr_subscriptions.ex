defmodule EyeInTheSky.Github.PrSubscriptions do
  @moduledoc false
  import Ecto.Query

  alias EyeInTheSky.Github.PrSubscription
  alias EyeInTheSky.Repo

  def subscribe(session_uuid, pr_number, repository_full_name) do
    attrs = %{
      session_uuid: session_uuid,
      pr_number: pr_number,
      repository_full_name: repository_full_name,
      active: true
    }

    %PrSubscription{}
    |> PrSubscription.changeset(attrs)
    |> Repo.insert(
      on_conflict: [set: [active: true]],
      conflict_target: [:session_uuid, :pr_number, :repository_full_name],
      returning: true
    )
  end

  def unsubscribe(session_uuid, pr_number, repository_full_name) do
    Repo.update_all(
      from(s in PrSubscription,
        where:
          s.session_uuid == ^session_uuid and
            s.pr_number == ^pr_number and
            s.repository_full_name == ^repository_full_name
      ),
      set: [active: false]
    )

    :ok
  end

  def subscribers_for(pr_number, repository_full_name) do
    Repo.all(
      from s in PrSubscription,
        where:
          s.pr_number == ^pr_number and
            s.repository_full_name == ^repository_full_name and
            s.active == true,
        limit: 200
    )
  end

end
