defmodule EyeInTheSkyWeb.Components.DmMessageComponentsTest do
  use EyeInTheSkyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmMessageComponents

  test "legacy DM sender tag links to the sender session" do
    sender_uuid = "123e4567-e89b-12d3-a456-426614174000"

    message = %{
      id: 1,
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
    sender_link = LazyHTML.query(document, ~s(a[href="/dm/#{sender_uuid}"]))

    assert LazyHTML.attribute(sender_link, "href") == ["/dm/#{sender_uuid}"]
  end
end
