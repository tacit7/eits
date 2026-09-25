defmodule EyeInTheSky.SessionIdleBroadcastTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.Factory
  alias EyeInTheSky.Sessions.{Session, StatusTransitions}

  test "setting a working session idle notifies status and working subscribers" do
    session = Factory.new_session()

    Phoenix.PubSub.subscribe(EyeInTheSky.PubSub, "agents")
    Phoenix.PubSub.subscribe(EyeInTheSky.PubSub, "agent:working")

    assert {:ok, updated} = StatusTransitions.set_session_idle(session)
    assert updated.status == "idle"
    assert Repo.get!(Session, session.id).status == "idle"
    assert_receive {:agent_stopped, ^updated}
    assert_receive {:agent_updated, ^updated}
  end
end
