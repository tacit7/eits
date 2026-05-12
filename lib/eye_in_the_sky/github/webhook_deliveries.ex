defmodule EyeInTheSky.Github.WebhookDeliveries do
  @moduledoc false
  import Ecto.Query

  alias EyeInTheSky.Github.WebhookDelivery
  alias EyeInTheSky.Repo

  def insert(attrs) do
    %WebhookDelivery{}
    |> WebhookDelivery.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, delivery} ->
        {:ok, delivery}

      {:error, changeset} ->
        if unique_constraint_error?(changeset, :delivery_id) do
          Repo.update_all(
            from(d in WebhookDelivery,
              where: d.delivery_id == ^attrs.delivery_id,
              update: [
                inc: [duplicate_count: 1],
                set: [last_duplicate_at: ^DateTime.utc_now()]
              ]
            ),
            []
          )

          delivery = Repo.get_by!(WebhookDelivery, delivery_id: attrs.delivery_id)
          {:duplicate, delivery}
        else
          {:error, changeset}
        end
    end
  end

  def claim(delivery_id) do
    now = DateTime.utc_now()

    {count, _} =
      Repo.update_all(
        from(d in WebhookDelivery,
          where: d.delivery_id == ^delivery_id and d.status == "pending",
          update: [
            set: [status: "processing", processing_started_at: ^now],
            inc: [attempt_count: 1]
          ]
        ),
        []
      )

    case count do
      1 -> {:ok, Repo.get_by!(WebhookDelivery, delivery_id: delivery_id)}
      _ -> {:error, :not_claimable}
    end
  end

  def mark_processed(id) do
    case Repo.update_all(
           from(d in WebhookDelivery,
             where: d.id == ^id,
             update: [set: [status: "processed", processed_at: ^DateTime.utc_now()]]
           ),
           []
         ) do
      {1, _} -> {:ok, Repo.get!(WebhookDelivery, id)}
      _ -> {:error, :not_found}
    end
  end

  def mark_failed(id, reason) do
    case Repo.update_all(
           from(d in WebhookDelivery,
             where: d.id == ^id,
             update: [set: [status: "failed", error_message: ^reason]]
           ),
           []
         ) do
      {1, _} -> {:ok, Repo.get!(WebhookDelivery, id)}
      _ -> {:error, :not_found}
    end
  end

  def pending do
    Repo.all(
      from d in WebhookDelivery,
        where: d.status == "pending",
        order_by: [asc: d.received_at],
        limit: 100
    )
  end

  def stale_processing(cutoff) do
    Repo.all(
      from d in WebhookDelivery,
        where: d.status == "processing" and d.processing_started_at < ^cutoff,
        limit: 100
    )
  end

  def reset_to_pending(id) do
    Repo.update_all(
      from(d in WebhookDelivery, where: d.id == ^id, update: [set: [status: "pending"]]),
      []
    )
  end

  defp unique_constraint_error?(changeset, field) do
    Enum.any?(changeset.errors, fn
      {^field, {_, opts}} -> Keyword.get(opts, :constraint) == :unique
      _ -> false
    end)
  end
end
