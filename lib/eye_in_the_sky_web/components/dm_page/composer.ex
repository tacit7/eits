defmodule EyeInTheSkyWeb.Components.DmPage.Composer do
  @moduledoc false

  use EyeInTheSkyWeb, :html

  alias EyeInTheSkyWeb.Components.DmPage.Composer.PromptQueue
  alias EyeInTheSkyWeb.Components.DmPage.MessageComposer

  defdelegate message_form(assigns), to: MessageComposer, as: :message_composer
  defdelegate prompt_queue(assigns), to: PromptQueue
end
