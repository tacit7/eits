defmodule EyeInTheSkyWeb.DmLive.UploadHelpersTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.DmLive.UploadHelpers

  describe "mime_from_ext/1" do
    test "returns correct MIME for image types" do
      assert UploadHelpers.mime_from_ext("photo.jpg") == "image/jpeg"
      assert UploadHelpers.mime_from_ext("photo.jpeg") == "image/jpeg"
      assert UploadHelpers.mime_from_ext("image.png") == "image/png"
      assert UploadHelpers.mime_from_ext("anim.gif") == "image/gif"
      assert UploadHelpers.mime_from_ext("pic.webp") == "image/webp"
    end

    test "returns correct MIME for document types" do
      assert UploadHelpers.mime_from_ext("report.pdf") == "application/pdf"
      assert UploadHelpers.mime_from_ext("notes.txt") == "text/plain"
      assert UploadHelpers.mime_from_ext("data.csv") == "text/csv"
      assert UploadHelpers.mime_from_ext("config.json") == "application/json"
      assert UploadHelpers.mime_from_ext("page.html") == "text/html"
      assert UploadHelpers.mime_from_ext("data.xml") == "text/xml"
    end

    test "returns application/octet-stream for unknown extensions" do
      assert UploadHelpers.mime_from_ext("archive.xyz") == "application/octet-stream"
    end

    test "is case-insensitive for extensions" do
      assert UploadHelpers.mime_from_ext("FILE.PDF") == "application/pdf"
      assert UploadHelpers.mime_from_ext("IMAGE.PNG") == "image/png"
    end
  end
end
