defmodule EyeInTheSky.Github.WebhookDeliveriesTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Github.WebhookDeliveries
  alias EyeInTheSky.Github.WebhookDelivery

  @valid_attrs %{
    delivery_id: "gh-delivery-uuid-1",
    hook_id: "hook-123",
    event_type: "pull_request.opened",
    event_header: "pull_request",
    action: "opened",
    repository_full_name: "tacit7/eits",
    sender_login: "uriel",
    payload: %{"action" => "opened"},
    received_at: DateTime.utc_now()
  }

  describe "insert/1" do
    test "inserts a new delivery with status=pending and attempt_count=0" do
      assert {:ok, %WebhookDelivery{} = d} = WebhookDeliveries.insert(@valid_attrs)
      assert d.status == "pending"
      assert d.attempt_count == 0
      assert d.duplicate_count == 0
    end

    test "on duplicate delivery_id, returns {:duplicate, delivery}" do
      {:ok, _} = WebhookDeliveries.insert(@valid_attrs)
      assert {:duplicate, d} = WebhookDeliveries.insert(@valid_attrs)
      assert d.duplicate_count == 1
      assert d.last_duplicate_at != nil
    end
  end

  describe "claim/1" do
    test "atomically claims a pending delivery and returns it" do
      {:ok, inserted} = WebhookDeliveries.insert(@valid_attrs)
      assert {:ok, claimed} = WebhookDeliveries.claim(inserted.delivery_id)
      assert claimed.status == "processing"
      assert claimed.attempt_count == 1
      assert claimed.processing_started_at != nil
    end

    test "returns {:error, :not_claimable} when already processing" do
      {:ok, inserted} = WebhookDeliveries.insert(@valid_attrs)
      {:ok, _} = WebhookDeliveries.claim(inserted.delivery_id)
      assert {:error, :not_claimable} = WebhookDeliveries.claim(inserted.delivery_id)
    end
  end

  describe "mark_processed/1" do
    test "sets status to processed and records processed_at" do
      {:ok, d} = WebhookDeliveries.insert(@valid_attrs)
      {:ok, d} = WebhookDeliveries.claim(d.delivery_id)
      assert {:ok, updated} = WebhookDeliveries.mark_processed(d.id)
      assert updated.status == "processed"
      assert updated.processed_at != nil
    end
  end

  describe "mark_failed/2" do
    test "sets status to failed with error message" do
      {:ok, d} = WebhookDeliveries.insert(@valid_attrs)
      {:ok, d} = WebhookDeliveries.claim(d.delivery_id)
      assert {:ok, updated} = WebhookDeliveries.mark_failed(d.id, "boom")
      assert updated.status == "failed"
      assert updated.error_message == "boom"
    end
  end

  describe "pending/0" do
    test "returns only pending deliveries ordered by received_at asc" do
      now = DateTime.utc_now()
      {:ok, _} = WebhookDeliveries.insert(%{@valid_attrs | delivery_id: "old", received_at: DateTime.add(now, -10)})
      {:ok, _} = WebhookDeliveries.insert(%{@valid_attrs | delivery_id: "new", received_at: now})

      ids = WebhookDeliveries.pending() |> Enum.map(& &1.delivery_id)
      assert ids == ["old", "new"]
    end
  end

  describe "stale_processing/1" do
    test "returns processing rows older than the given cutoff" do
      {:ok, d} = WebhookDeliveries.insert(@valid_attrs)
      {:ok, claimed} = WebhookDeliveries.claim(d.delivery_id)

      past = DateTime.add(DateTime.utc_now(), 600)
      stale = WebhookDeliveries.stale_processing(past)
      assert Enum.any?(stale, &(&1.id == claimed.id))
    end
  end
end
