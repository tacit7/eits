defmodule EyeInTheSky.IAM.Builtin.BlockGcloudTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.IAM.Builtin.BlockGcloud
  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  defp ctx(cmd), do: %Context{tool: "Bash", resource_content: cmd}

  test "blocks gcloud compute instances delete" do
    assert BlockGcloud.matches?(%Policy{}, ctx("gcloud compute instances delete my-vm --zone us-central1-a"))
  end

  test "blocks gcloud projects delete" do
    assert BlockGcloud.matches?(%Policy{}, ctx("gcloud projects delete my-project"))
  end

  test "blocks gcloud sql instances delete" do
    assert BlockGcloud.matches?(%Policy{}, ctx("gcloud sql instances delete my-db"))
  end

  test "blocks gcloud container clusters delete" do
    assert BlockGcloud.matches?(%Policy{}, ctx("gcloud container clusters delete my-cluster"))
  end

  test "blocks gcloud functions delete" do
    assert BlockGcloud.matches?(%Policy{}, ctx("gcloud functions delete my-function"))
  end

  test "blocks gcloud run services delete" do
    assert BlockGcloud.matches?(%Policy{}, ctx("gcloud run services delete my-service"))
  end

  test "does not block gcloud compute instances list" do
    refute BlockGcloud.matches?(%Policy{}, ctx("gcloud compute instances list"))
  end

  test "does not block gcloud projects list" do
    refute BlockGcloud.matches?(%Policy{}, ctx("gcloud projects list"))
  end

  test "does not match non-Bash tool" do
    refute BlockGcloud.matches?(%Policy{}, %Context{tool: "Write", resource_content: "gcloud projects delete x"})
  end
end
