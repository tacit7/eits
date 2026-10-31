defmodule EyeInTheSkyWeb.Components.DmMessageComponentsTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmMessageComponents

  test "formats DM headers when the sender name contains parentheses" do
    sender = "chirpi M0 review (codex astra)"
    body = "## Review findings\n\n- **Ready** for M0.\n- Run `mix test`."

    message = %{
      id: 2,
      from_session_id: 7353,
      sender_role: "agent",
      body: "DM from:#{sender} (session:01a192ba-7568-7202-ad1c-47e7efac1805) #{body}",
      metadata: %{},
      attachments: []
    }

    document =
      render_component(&DmMessageComponents.message_body/1, message: message)
      |> LazyHTML.from_fragment()

    sender_link = LazyHTML.query(document, ~s(a[href="/dm/7353"]))
    assert LazyHTML.text(sender_link) =~ sender

    markdown = LazyHTML.query(document, ~s([id^="msg-body-2-"][phx-hook=MarkdownMessage]))
    assert markdown |> LazyHTML.attribute("data-raw-body") |> Enum.join("\n\n") == body
  end

  test "legacy DM sender tag links to the sender session" do
    sender_uuid = "123e4567-e89b-12d3-a456-426614174000"
    sender_id = 42

    message = %{
      id: 1,
      from_session_id: sender_id,
      sender_role: "agent",
      body: "DM from:researcher (session:#{sender_uuid}) Finished the review.",
      metadata: %{},
      attachments: []
    }

    html =
      render_component(&DmMessageComponents.message_body/1,
        message: message,
        compact: false,
        flat: false
      )

    document = LazyHTML.from_fragment(html)
    sender_link = LazyHTML.query(document, ~s(a[href="/dm/#{sender_id}"]))

    assert LazyHTML.attribute(sender_link, "href") == ["/dm/#{sender_id}"]
    assert LazyHTML.text(sender_link) =~ "##{sender_id}"

    assert LazyHTML.attribute(LazyHTML.query(document, ~s(a[href="/dm/#{sender_uuid}"])), "href") ==
             []
  end
end
