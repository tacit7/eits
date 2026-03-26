defmodule EyeInTheSky.Claude.ContentBlock do
  @moduledoc """
  Structured content blocks for multimodal messages.

  Supports text, image (base64), and document content types.
  """

  defmodule Text do
    @moduledoc "A plain text content block."
    @enforce_keys [:text]
    defstruct [:text]
  end

  defmodule Image do
    @moduledoc "A base64-encoded image content block."
    @enforce_keys [:data, :mime_type]
    defstruct [:data, :mime_type]
  end

  defmodule Document do
    @moduledoc "A document content block with a source map."
    @enforce_keys [:source]
    defstruct [:source]
  end

  @type t() :: %Text{} | %Image{} | %Document{}

  @doc "Returns true if the block is a Text block."
  @spec text?(term()) :: boolean()
  def text?(%Text{}), do: true
  def text?(_), do: false

  @doc "Returns true if the block is an Image block."
  @spec image?(term()) :: boolean()
  def image?(%Image{}), do: true
  def image?(_), do: false

  @doc "Returns true if the block is a Document block."
  @spec document?(term()) :: boolean()
  def document?(%Document{}), do: true
  def document?(_), do: false

  @doc "Constructs a Text content block."
  @spec new_text(String.t()) :: %Text{}
  def new_text(text), do: %Text{text: text}

  @doc "Constructs an Image content block."
  @spec new_image(String.t(), String.t()) :: %Image{}
  def new_image(data, mime_type), do: %Image{data: data, mime_type: mime_type}

  @doc "Constructs a Document content block."
  @spec new_document(String.t(), map()) :: %Document{}
  def new_document(media_type, data) do
    %Document{source: %{type: "base64", media_type: media_type, data: data}}
  end
end
