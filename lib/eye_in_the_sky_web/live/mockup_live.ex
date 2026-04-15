defmodule EyeInTheSkyWeb.MockupLive do
  use EyeInTheSkyWeb, :live_view

  @mockup_path Path.join([File.cwd!(), ".superpowers", "brainstorm", "mockup.html"])
  @poll_interval 1_500

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_poll()

    {html, mtime} = read_mockup()

    {:ok,
     socket
     |> assign(:html, html)
     |> assign(:mtime, mtime), layout: false}
  end

  @impl true
  def handle_info(:poll, socket) do
    schedule_poll()
    {html, mtime} = read_mockup()

    if mtime != socket.assigns.mtime do
      {:noreply, assign(socket, html: html, mtime: mtime)}
    else
      {:noreply, socket}
    end
  end

  defp schedule_poll, do: Process.send_after(self(), :poll, @poll_interval)

  defp read_mockup do
    case File.stat(@mockup_path) do
      {:ok, %{mtime: mtime}} ->
        html = File.read!(@mockup_path)
        {html, mtime}

      {:error, _} ->
        {default_html(), nil}
    end
  end

  defp default_html do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8" />
      <title>Mockup</title>
      <style>
        body { font-family: system-ui, sans-serif; background: #0f0f0f; color: #ccc;
               display: flex; align-items: center; justify-content: center;
               min-height: 100vh; margin: 0; }
        p { opacity: 0.4; font-size: 14px; }
      </style>
    </head>
    <body><p>Waiting for mockup...</p></body>
    </html>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <iframe
      srcdoc={@html}
      style="width:100vw;height:100vh;border:none;display:block;"
      sandbox="allow-scripts allow-same-origin"
    >
    </iframe>
    """
  end
end
