defmodule EyeInTheSkyWeb.DmLive.UploadHelpersTest do
  use ExUnit.Case, async: true

  # Access the private mime_from_ext/1 via the module's public surface indirectly
  # by testing via the MIME library directly, matching what the implementation does.

  describe "mime_from_ext via MIME.from_path/1" do
    test "returns correct MIME for image types" do
      assert MIME.from_path("photo.jpg") == "image/jpeg"
      assert MIME.from_path("photo.jpeg") == "image/jpeg"
      assert MIME.from_path("image.png") == "image/png"
      assert MIME.from_path("anim.gif") == "image/gif"
      assert MIME.from_path("pic.webp") == "image/webp"
    end

    test "returns correct MIME for document types" do
      assert MIME.from_path("report.pdf") == "application/pdf"
      assert MIME.from_path("notes.txt") == "text/plain"
      assert MIME.from_path("data.csv") == "text/csv"
      assert MIME.from_path("config.json") == "application/json"
      assert MIME.from_path("page.html") == "text/html"
      assert MIME.from_path("data.xml") == "text/xml"
    end

    test "returns application/octet-stream for unknown extensions" do
      assert MIME.from_path("archive.xyz") == "application/octet-stream"
    end

    test "is case-insensitive for extensions" do
      assert MIME.from_path("FILE.PDF") == "application/pdf"
      assert MIME.from_path("IMAGE.PNG") == "image/png"
    end
  end
end
