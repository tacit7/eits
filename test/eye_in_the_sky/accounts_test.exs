defmodule EyeInTheSky.AccountsTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Accounts
  alias EyeInTheSky.Accounts.{ApiKey, UserSession}

  # ---------------------------------------------------------------------------
  # User operations
  # ---------------------------------------------------------------------------

  describe "get_user/1" do
    test "returns the user when found" do
      {:ok, user} = Accounts.get_or_create_user("get_user_test_#{uniq()}")
      assert {:ok, found} = Accounts.get_user(user.id)
      assert found.id == user.id
    end

    test "returns error when user does not exist" do
      assert {:error, :not_found} = Accounts.get_user(0)
    end
  end

  describe "get_user_by_username/1" do
    test "returns the user for a known username" do
      username = "by_username_#{uniq()}"
      {:ok, user} = Accounts.get_or_create_user(username)
      assert {:ok, found} = Accounts.get_user_by_username(username)
      assert found.id == user.id
    end

    test "returns error for unknown username" do
      assert {:error, :not_found} = Accounts.get_user_by_username("nobody_#{uniq()}")
    end
  end

  describe "get_or_create_user/1" do
    test "creates a new user when username is not taken" do
      username = "new_user_#{uniq()}"
      assert {:ok, user} = Accounts.get_or_create_user(username)
      assert user.username == username
    end

    test "returns the existing user when username already exists" do
      username = "existing_#{uniq()}"
      {:ok, first} = Accounts.get_or_create_user(username)
      {:ok, second} = Accounts.get_or_create_user(username)
      assert first.id == second.id
    end

    test "sets display_name equal to username on creation" do
      username = "display_#{uniq()}"
      {:ok, user} = Accounts.get_or_create_user(username)
      assert user.display_name == username
    end
  end

  # ---------------------------------------------------------------------------
  # Passkey operations
  # ---------------------------------------------------------------------------

  describe "list_passkeys_for_user/1" do
    test "returns empty list when user has no passkeys" do
      {:ok, user} = Accounts.get_or_create_user("no_passkeys_#{uniq()}")
      assert Accounts.list_passkeys_for_user(user.id) == []
    end

    test "returns all passkeys belonging to the user" do
      {:ok, user} = Accounts.get_or_create_user("has_passkeys_#{uniq()}")
      {:ok, _pk1} = Accounts.create_passkey(passkey_attrs(user.id))
      {:ok, _pk2} = Accounts.create_passkey(passkey_attrs(user.id))
      passkeys = Accounts.list_passkeys_for_user(user.id)
      assert length(passkeys) == 2
    end

    test "does not return passkeys belonging to another user" do
      {:ok, user_a} = Accounts.get_or_create_user("user_a_#{uniq()}")
      {:ok, user_b} = Accounts.get_or_create_user("user_b_#{uniq()}")
      {:ok, _pk} = Accounts.create_passkey(passkey_attrs(user_a.id))
      assert Accounts.list_passkeys_for_user(user_b.id) == []
    end
  end

  describe "get_passkey_by_credential_id/1" do
    test "returns the passkey for a known credential_id" do
      {:ok, user} = Accounts.get_or_create_user("cred_user_#{uniq()}")
      attrs = passkey_attrs(user.id)
      {:ok, _pk} = Accounts.create_passkey(attrs)
      assert {:ok, found} = Accounts.get_passkey_by_credential_id(attrs.credential_id)
      assert found.user_id == user.id
    end

    test "returns error for unknown credential_id" do
      assert {:error, :not_found} =
               Accounts.get_passkey_by_credential_id(:crypto.strong_rand_bytes(16))
    end
  end

  describe "create_passkey/1" do
    test "inserts a passkey with required fields" do
      {:ok, user} = Accounts.get_or_create_user("create_pk_#{uniq()}")
      assert {:ok, pk} = Accounts.create_passkey(passkey_attrs(user.id))
      assert pk.user_id == user.id
      assert pk.sign_count == 0
    end

    test "returns changeset error when credential_id is missing" do
      {:ok, user} = Accounts.get_or_create_user("pk_missing_cred_#{uniq()}")

      assert {:error, changeset} =
               Accounts.create_passkey(%{user_id: user.id, cose_key: sample_cose_key()})

      assert %{credential_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns changeset error on duplicate credential_id" do
      {:ok, user} = Accounts.get_or_create_user("pk_dup_#{uniq()}")
      attrs = passkey_attrs(user.id)
      {:ok, _} = Accounts.create_passkey(attrs)
      assert {:error, changeset} = Accounts.create_passkey(attrs)
      assert %{credential_id: [_]} = errors_on(changeset)
    end
  end

  describe "update_sign_count/2" do
    test "updates the sign_count on the passkey" do
      {:ok, user} = Accounts.get_or_create_user("sign_count_#{uniq()}")
      {:ok, pk} = Accounts.create_passkey(passkey_attrs(user.id))
      assert {:ok, updated} = Accounts.update_sign_count(pk, 5)
      assert updated.sign_count == 5
    end
  end

  describe "build_allowed_credentials/1" do
    test "returns empty list when user has no passkeys" do
      {:ok, user} = Accounts.get_or_create_user("build_creds_empty_#{uniq()}")
      assert Accounts.build_allowed_credentials(user.id) == []
    end

    test "returns credential_id and decoded cose_key tuples" do
      {:ok, user} = Accounts.get_or_create_user("build_creds_full_#{uniq()}")
      cose_term = %{1 => 2, -1 => 3}
      attrs = %{passkey_attrs(user.id) | cose_key: :erlang.term_to_binary(cose_term)}
      {:ok, _pk} = Accounts.create_passkey(attrs)
      [{cred_id, decoded_key}] = Accounts.build_allowed_credentials(user.id)
      assert is_binary(cred_id)
      assert decoded_key == cose_term
    end
  end

  # ---------------------------------------------------------------------------
  # Registration tokens
  # ---------------------------------------------------------------------------

  describe "create_registration_token/2" do
    test "returns a raw token, and the stored token is hashed" do
      assert {:ok, raw_token, rt} = Accounts.create_registration_token("alice_#{uniq()}")
      assert is_binary(raw_token)
      assert raw_token != rt.token
    end

    test "token expires after the requested TTL" do
      {:ok, _raw, rt} = Accounts.create_registration_token("ttl_#{uniq()}", 1)
      diff_seconds = NaiveDateTime.diff(rt.expires_at, NaiveDateTime.utc_now(), :second)
      assert diff_seconds > 0 and diff_seconds <= 60
    end

    test "defaults to 15-minute TTL" do
      {:ok, _raw, rt} = Accounts.create_registration_token("ttl_default_#{uniq()}")
      diff_seconds = NaiveDateTime.diff(rt.expires_at, NaiveDateTime.utc_now(), :second)
      assert diff_seconds > 800 and diff_seconds <= 900
    end
  end

  describe "peek_registration_token/1" do
    test "returns the username for a valid, unexpired token" do
      username = "peek_valid_#{uniq()}"
      {:ok, raw_token, _} = Accounts.create_registration_token(username)
      assert {:ok, ^username} = Accounts.peek_registration_token(raw_token)
    end

    test "returns error for an unknown token" do
      fake_token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      assert {:error, :not_found} = Accounts.peek_registration_token(fake_token)
    end

    test "returns error for an expired token without deleting it" do
      username = "peek_expired_#{uniq()}"
      {:ok, raw_token, rt} = Accounts.create_registration_token(username)

      # Back-date the expiry to the past via direct Repo update
      expired_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.truncate(:second)
        |> NaiveDateTime.add(-60, :second)

      Repo.update!(Ecto.Changeset.change(rt, expires_at: expired_at))

      assert {:error, :expired} = Accounts.peek_registration_token(raw_token)
      # Token still exists in DB (peek does not consume it)
      assert Repo.get_by(EyeInTheSky.Accounts.RegistrationToken, id: rt.id) != nil
    end

    test "does not consume the token — repeated peeks succeed" do
      username = "peek_repeat_#{uniq()}"
      {:ok, raw_token, _} = Accounts.create_registration_token(username)
      assert {:ok, ^username} = Accounts.peek_registration_token(raw_token)
      assert {:ok, ^username} = Accounts.peek_registration_token(raw_token)
    end
  end

  describe "consume_registration_token/1" do
    test "returns the username and deletes the token" do
      username = "consume_valid_#{uniq()}"
      {:ok, raw_token, rt} = Accounts.create_registration_token(username)
      assert {:ok, ^username} = Accounts.consume_registration_token(raw_token)
      assert Repo.get_by(EyeInTheSky.Accounts.RegistrationToken, id: rt.id) == nil
    end

    test "returns error for unknown token" do
      fake_token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      assert {:error, :not_found} = Accounts.consume_registration_token(fake_token)
    end

    test "returns error for expired token and still deletes it" do
      username = "consume_expired_#{uniq()}"
      {:ok, raw_token, rt} = Accounts.create_registration_token(username)

      expired_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.truncate(:second)
        |> NaiveDateTime.add(-60, :second)

      Repo.update!(Ecto.Changeset.change(rt, expires_at: expired_at))

      assert {:error, :expired} = Accounts.consume_registration_token(raw_token)
      # Expired tokens are cleaned up on consume
      assert Repo.get_by(EyeInTheSky.Accounts.RegistrationToken, id: rt.id) == nil
    end

    test "is one-time use — second consume returns not_found" do
      username = "consume_once_#{uniq()}"
      {:ok, raw_token, _} = Accounts.create_registration_token(username)
      assert {:ok, ^username} = Accounts.consume_registration_token(raw_token)
      assert {:error, :not_found} = Accounts.consume_registration_token(raw_token)
    end
  end

  # ---------------------------------------------------------------------------
  # User sessions
  # ---------------------------------------------------------------------------

  describe "create_user_session/1" do
    test "returns a token string on success" do
      {:ok, user} = Accounts.get_or_create_user("sess_create_#{uniq()}")
      assert {:ok, token} = Accounts.create_user_session(user.id)
      assert is_binary(token) and byte_size(token) > 0
    end

    test "session expires 7 days from now" do
      {:ok, user} = Accounts.get_or_create_user("sess_ttl_#{uniq()}")
      {:ok, token} = Accounts.create_user_session(user.id)
      session = Repo.get_by!(UserSession, session_token: token)

      diff_days =
        NaiveDateTime.diff(session.expires_at, NaiveDateTime.utc_now(), :second) / 86_400

      assert diff_days > 6.9 and diff_days <= 7.1
    end
  end

  describe "get_valid_user_session/1" do
    test "returns the session for a valid, unexpired token" do
      {:ok, user} = Accounts.get_or_create_user("sess_valid_#{uniq()}")
      {:ok, token} = Accounts.create_user_session(user.id)
      assert {:ok, session} = Accounts.get_valid_user_session(token)
      assert session.session_token == token
    end

    test "returns error for unknown token" do
      assert {:error, :not_found} = Accounts.get_valid_user_session("nonexistent_token_#{uniq()}")
    end

    test "returns error for an expired session" do
      {:ok, user} = Accounts.get_or_create_user("sess_expired_#{uniq()}")
      {:ok, token} = Accounts.create_user_session(user.id)
      session = Repo.get_by!(UserSession, session_token: token)

      expired_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.truncate(:second)
        |> NaiveDateTime.add(-3600, :second)

      Repo.update!(Ecto.Changeset.change(session, expires_at: expired_at))
      assert {:error, :expired} = Accounts.get_valid_user_session(token)
    end
  end

  describe "delete_user_session/1" do
    test "removes an existing session and returns :ok" do
      {:ok, user} = Accounts.get_or_create_user("sess_delete_#{uniq()}")
      {:ok, token} = Accounts.create_user_session(user.id)
      assert :ok = Accounts.delete_user_session(token)
      assert Repo.get_by(UserSession, session_token: token) == nil
    end

    test "returns :ok even when session does not exist" do
      assert :ok = Accounts.delete_user_session("no_such_token_#{uniq()}")
    end

    test "deleting one session does not affect other sessions for the same user" do
      {:ok, user} = Accounts.get_or_create_user("multi_sess_#{uniq()}")
      {:ok, token_a} = Accounts.create_user_session(user.id)
      {:ok, token_b} = Accounts.create_user_session(user.id)
      Accounts.delete_user_session(token_a)
      assert {:ok, _} = Accounts.get_valid_user_session(token_b)
    end
  end

  # ---------------------------------------------------------------------------
  # ApiKey (Accounts.ApiKey module)
  # ---------------------------------------------------------------------------

  describe "ApiKey.create/2 and valid_db_token?/1" do
    test "valid_db_token? returns true for a freshly created key" do
      token = "test_key_#{uniq()}"
      {:ok, _} = ApiKey.create(token, "label_#{uniq()}")
      assert ApiKey.valid_db_token?(token)
    end

    test "valid_db_token? returns false for an unknown token" do
      refute ApiKey.valid_db_token?("unknown_#{uniq()}")
    end

    test "valid_db_token? returns false for an expired key" do
      token = "expired_key_#{uniq()}"
      past = NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)
      {:ok, _} = ApiKey.create(token, "expired_label_#{uniq()}", past)
      refute ApiKey.valid_db_token?(token)
    end

    test "valid_db_token? returns true for a key with nil valid_until (never expires)" do
      token = "neverexpires_#{uniq()}"
      {:ok, _} = ApiKey.create(token, "permanent_#{uniq()}", nil)
      assert ApiKey.valid_db_token?(token)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp uniq, do: System.unique_integer([:positive])

  defp passkey_attrs(user_id) do
    %{
      user_id: user_id,
      credential_id: :crypto.strong_rand_bytes(16),
      cose_key: sample_cose_key(),
      sign_count: 0
    }
  end

  defp sample_cose_key do
    :erlang.term_to_binary(%{1 => 2, -1 => 3})
  end
end
