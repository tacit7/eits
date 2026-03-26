defmodule EyeInTheSky.Media.ImageProcessor do
  @moduledoc """
  Image preprocessing for multimodal content blocks.

  Resizes, compresses, and normalizes images before they are sent to
  provider APIs. Uses ImageMagick (convert) for processing when available,
  falls through as-is when not installed.

  ## Limits (from Open Claw reference)

  - Hard limit: 6MB per image
  - API target: 5MB after processing
  - Max dimension: 1200px default, 2000px for single-image requests
  - EXIF orientation auto-normalized
  - Converts to JPEG for compression (except PNG with transparency)
  """

  alias EyeInTheSky.Claude.ContentBlock

  require Logger

  @hard_limit_bytes 6 * 1024 * 1024
  @target_bytes 5 * 1024 * 1024
  @max_dimension 1200
  @single_image_max_dimension 2000
  @quality_steps [85, 75, 65, 55, 45, 35]

  @doc """
  Processes a list of ContentBlock.Image structs, resizing and compressing
  as needed to fit within API limits. Returns the processed list.

  Non-image blocks are passed through unchanged.
  """
  @spec process_blocks([ContentBlock.t()]) :: [ContentBlock.t()]
  def process_blocks([]), do: []

  def process_blocks(blocks) when is_list(blocks) do
    image_count = Enum.count(blocks, &ContentBlock.image?/1)
    max_dim = if image_count == 1, do: @single_image_max_dimension, else: @max_dimension

    Enum.map(blocks, fn block ->
      if ContentBlock.image?(block) do
        process_image(block, max_dim)
      else
        block
      end
    end)
  end

  @doc """
  Processes a single image block. Returns the block unchanged if already
  within limits or if ImageMagick is not available. Gracefully handles
  invalid base64 data by returning the block as-is.
  """
  @spec process_image(ContentBlock.Image.t(), pos_integer()) :: ContentBlock.Image.t()
  def process_image(%ContentBlock.Image{data: data, mime_type: mime_type} = block, max_dim \\ @max_dimension) do
    case Base.decode64(data) do
      {:ok, raw} ->
        raw_size = byte_size(raw)

        cond do
          raw_size > @hard_limit_bytes ->
            Logger.warning("[ImageProcessor] Image exceeds hard limit (#{raw_size} bytes), attempting resize")
            resize_and_compress(raw, mime_type, max_dim)

          raw_size > @target_bytes ->
            Logger.info("[ImageProcessor] Image above target (#{raw_size} bytes), compressing")
            resize_and_compress(raw, mime_type, max_dim)

          true ->
            # Within limits, just normalize EXIF orientation
            case auto_orient(raw, mime_type) do
              {:ok, oriented} -> %ContentBlock.Image{data: Base.encode64(oriented), mime_type: mime_type}
              :error -> block
            end
        end

      :error ->
        Logger.warning("[ImageProcessor] Invalid base64 data, passing through unchanged")
        block
    end
  end

  defp resize_and_compress(raw, mime_type, max_dim) do
    case imagemagick_available?() do
      false ->
        Logger.warning("[ImageProcessor] ImageMagick not available, passing through as-is")
        %ContentBlock.Image{data: Base.encode64(raw), mime_type: mime_type}

      true ->
        do_resize_and_compress(raw, mime_type, max_dim)
    end
  end

  defp do_resize_and_compress(raw, original_mime_type, max_dim) do
    src = temp_path("src")
    File.write!(src, raw)

    result =
      Enum.reduce_while(@quality_steps, nil, fn quality, _acc ->
        dst = temp_path("dst.jpg")

        args = [
          src,
          "-auto-orient",
          "-resize", "#{max_dim}x#{max_dim}>",
          "-quality", to_string(quality),
          "-strip",
          dst
        ]

        case System.cmd("convert", args, stderr_to_stdout: true) do
          {_, 0} ->
            case File.read(dst) do
              {:ok, processed} ->
                File.rm(dst)

                if byte_size(processed) <= @target_bytes do
                  {:halt, {:ok, processed, quality}}
                else
                  {:cont, nil}
                end

              {:error, _} ->
                File.rm(dst)
                {:cont, nil}
            end

          {err, _} ->
            Logger.warning("[ImageProcessor] convert failed: #{err}")
            File.rm(dst)
            {:halt, :error}
        end
      end)

    File.rm(src)

    case result do
      {:ok, processed, quality} ->
        Logger.info("[ImageProcessor] Compressed to #{byte_size(processed)} bytes at quality #{quality}")
        %ContentBlock.Image{data: Base.encode64(processed), mime_type: "image/jpeg"}

      _ ->
        # Fallback: return original data with original mime type (not forced jpeg)
        Logger.warning("[ImageProcessor] All quality steps exceeded target, using original")
        %ContentBlock.Image{data: Base.encode64(raw), mime_type: original_mime_type}
    end
  end

  defp auto_orient(raw, _mime_type) do
    case imagemagick_available?() do
      false ->
        :error

      true ->
        src = temp_path("orient_src")
        dst = temp_path("orient_dst")
        File.write!(src, raw)

        case System.cmd("convert", [src, "-auto-orient", "-strip", dst], stderr_to_stdout: true) do
          {_, 0} ->
            result = File.read(dst)
            File.rm(src)
            File.rm(dst)
            result

          _ ->
            File.rm(src)
            File.rm(dst)
            :error
        end
    end
  end

  defp imagemagick_available? do
    case System.find_executable("convert") do
      nil -> false
      _ -> true
    end
  end

  defp temp_path(suffix) do
    Path.join(System.tmp_dir!(), "eits_img_#{:erlang.unique_integer([:positive])}_#{suffix}")
  end
end
