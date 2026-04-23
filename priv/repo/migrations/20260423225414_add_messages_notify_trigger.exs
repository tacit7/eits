defmodule EyeInTheSky.Repo.Migrations.AddMessagesNotifyTrigger do
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION messages_notify() RETURNS trigger AS $$
    BEGIN
      PERFORM pg_notify('messages_inserted', NEW.id::text);
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER messages_notify_after_insert
      AFTER INSERT ON messages
      FOR EACH ROW EXECUTE FUNCTION messages_notify();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS messages_notify_after_insert ON messages;")
    execute("DROP FUNCTION IF EXISTS messages_notify();")
  end
end
