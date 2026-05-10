defmodule EyeInTheSky.FileAttachmentsTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.{Agents, FileAttachments, Messages, Sessions}
  alias EyeInTheSky.Messages.FileAttachment

  defp uniq, do: System.unique_integer([:positive])

  defp create_session do
    {:ok, agent} = Agents.create_agent(%{name: "fa-agent-#{uniq()}", status: "active"})

    {:ok, session} =
      Sessions.create_session(%{
        uuid: Ecto.UUID.generate(),
        agent_id: agent.id,
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "idle"
      })

    session
  end

  defp create_message(session_id) do
    {:ok, msg} =
      Messages.create_message(%{
        uuid: Ecto.UUID.generate(),
        session_id: session_id,
        sender_role: "user",
        recipient_role: "agent",
        direction: "outbound",
        body: "with attachment",
        status: "sent",
        provider: "claude"
      })

    msg
  end

  defp tmp_file(content \\ "data") do
    path = Path.join(System.tmp_dir!(), "fa_test_#{uniq()}.txt")
    File.write!(path, content)
    path
  end

  defp valid_attrs(message_id, overrides \\ %{}) do
    Map.merge(
      %{
        message_id: message_id,
        filename: "stored_#{uniq()}.txt",
        original_filename: "original.txt",
        content_type: "text/plain",
        size_bytes: 4,
        storage_path: tmp_file(),
        upload_session_id: "upl_#{uniq()}"
      },
      overrides
    )
  end

  describe "create_attachment/1" do
    setup do
      session = create_session()
      msg = create_message(session.id)
      %{message: msg}
    end

    test "creates with auto-generated uuid and timestamps", %{message: msg} do
      attrs = valid_attrs(msg.id) |> Map.delete(:uuid)
      assert {:ok, %FileAttachment{} = att} = FileAttachments.create_attachment(attrs)
      assert att.uuid != nil
      assert att.message_id == msg.id
      assert att.original_filename == "original.txt"
      assert att.inserted_at != nil
      assert att.updated_at != nil
    end

    test "respects an explicitly provided uuid", %{message: msg} do
      uuid = Ecto.UUID.generate()
      attrs = valid_attrs(msg.id) |> Map.put(:uuid, uuid)
      assert {:ok, att} = FileAttachments.create_attachment(attrs)
      assert att.uuid == uuid
    end

    test "always overwrites inserted_at/updated_at with the current timestamp", %{message: msg} do
      old = ~U[2000-01-01 00:00:00Z]
      attrs = valid_attrs(msg.id) |> Map.put(:inserted_at, old) |> Map.put(:updated_at, old)
      assert {:ok, att} = FileAttachments.create_attachment(attrs)
      refute DateTime.compare(att.inserted_at, old) == :eq
      refute DateTime.compare(att.updated_at, old) == :eq
    end

    test "returns {:error, changeset} when required fields are missing", %{message: msg} do
      attrs =
        valid_attrs(msg.id)
        |> Map.delete(:filename)
        |> Map.delete(:original_filename)
        |> Map.delete(:storage_path)

      assert {:error, %Ecto.Changeset{valid?: false} = cs} = FileAttachments.create_attachment(attrs)
      errors = errors_on(cs)
      assert errors[:filename]
      assert errors[:original_filename]
      assert errors[:storage_path]
    end

    test "validates size_bytes upper bound (50MB)", %{message: msg} do
      attrs = valid_attrs(msg.id) |> Map.put(:size_bytes, 52_428_801)
      assert {:error, %Ecto.Changeset{} = cs} = FileAttachments.create_attachment(attrs)
      assert errors_on(cs)[:size_bytes]
    end

    test "validates size_bytes must be greater than 0", %{message: msg} do
      attrs = valid_attrs(msg.id) |> Map.put(:size_bytes, 0)
      assert {:error, %Ecto.Changeset{} = cs} = FileAttachments.create_attachment(attrs)
      assert errors_on(cs)[:size_bytes]
    end
  end

  describe "delete_attachment/1 with a struct" do
    setup do
      session = create_session()
      msg = create_message(session.id)
      %{message: msg}
    end

    test "deletes both the file on disk and the DB record", %{message: msg} do
      path = tmp_file("contents")
      assert File.exists?(path)

      {:ok, att} =
        FileAttachments.create_attachment(valid_attrs(msg.id) |> Map.put(:storage_path, path))

      assert :ok = FileAttachments.delete_attachment(att)
      refute File.exists?(path)
      assert Repo.get(FileAttachment, att.id) == nil
    end

    test "still deletes the DB record when the file is already missing", %{message: msg} do
      path = tmp_file()
      {:ok, att} =
        FileAttachments.create_attachment(valid_attrs(msg.id) |> Map.put(:storage_path, path))

      File.rm!(path)
      refute File.exists?(path)

      assert :ok = FileAttachments.delete_attachment(att)
      assert Repo.get(FileAttachment, att.id) == nil
    end

    test "returns {:error, {:file_delete_failed, _}} and keeps the DB row when rm fails", %{
      message: msg
    } do
      # Path that is a directory — File.rm/1 returns {:error, :eperm} or :eisdir.
      dir = Path.join(System.tmp_dir!(), "fa_dir_#{uniq()}")
      File.mkdir_p!(dir)

      {:ok, att} =
        FileAttachments.create_attachment(valid_attrs(msg.id) |> Map.put(:storage_path, dir))

      assert {:error, {:file_delete_failed, _reason}} = FileAttachments.delete_attachment(att)
      # DB record should still be present
      assert Repo.get(FileAttachment, att.id) != nil

      File.rmdir(dir)
    end
  end

  describe "delete_attachment/1 with an integer id" do
    setup do
      session = create_session()
      msg = create_message(session.id)
      %{message: msg}
    end

    test "looks up by id and deletes both file and record", %{message: msg} do
      path = tmp_file("xyz")
      {:ok, att} =
        FileAttachments.create_attachment(valid_attrs(msg.id) |> Map.put(:storage_path, path))

      assert :ok = FileAttachments.delete_attachment(att.id)
      refute File.exists?(path)
      assert Repo.get(FileAttachment, att.id) == nil
    end

    test "returns {:error, :not_found} for an unknown id" do
      assert {:error, :not_found} = FileAttachments.delete_attachment(-1)
    end
  end
end
