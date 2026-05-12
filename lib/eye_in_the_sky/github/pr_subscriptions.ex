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

    case %PrSubscription{} |> PrSubscription.changeset(attrs) |> Repo.insert() do
      {:ok, sub} ->
        {:ok, sub}

      {:error, %Ecto.Changeset{errors: [_ | _]} = cs} ->
        if unique_conflict?(cs) do
          # Idempotent: activate if it was previously deactivated
          existing = get_by(session_uuid, pr_number, repository_full_name)
          if existing && !existing.active do
            existing |> Ecto.Changeset.change(active: true) |> Repo.update()
          else
            {:ok, existing}
          end
        else
          {:error, cs}
        end
    end
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

  defp get_by(session_uuid, pr_number, repository_full_name) do
    Repo.one(
      from s in PrSubscription,
        where:
          s.session_uuid == ^session_uuid and
            s.pr_number == ^pr_number and
            s.repository_full_name == ^repository_full_name,
        limit: 1
    )
  end

  defp unique_conflict?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_msg, opts}} ->
      opts[:constraint] == :unique
    end)
  end
end
