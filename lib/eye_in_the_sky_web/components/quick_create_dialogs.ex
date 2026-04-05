defmodule EyeInTheSkyWeb.Components.QuickCreateDialogs do
  @moduledoc false
  use Phoenix.Component

  alias EyeInTheSkyWeb.Components.QuickCreateDialogs.{
    AgentDialog,
    ChatDialog,
    DeleteAgentDialog,
    GetAgentDialog,
    NoteDialog,
    ResumeAgentDialog,
    TaskDialog,
    UpdateAgentDialog
  }

  defdelegate quick_create_note(assigns), to: NoteDialog
  defdelegate quick_update_agent(assigns), to: UpdateAgentDialog
  defdelegate quick_get_agent(assigns), to: GetAgentDialog
  defdelegate quick_delete_agent(assigns), to: DeleteAgentDialog
  defdelegate quick_resume_agent(assigns), to: ResumeAgentDialog

  attr :project_id, :any, default: nil
  def quick_create_agent(assigns), do: AgentDialog.quick_create_agent(assigns)

  attr :project_id, :any, default: nil
  def quick_create_chat(assigns), do: ChatDialog.quick_create_chat(assigns)

  attr :project_id, :any, default: nil
  def quick_create_task(assigns), do: TaskDialog.quick_create_task(assigns)
end
