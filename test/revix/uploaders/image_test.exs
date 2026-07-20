defmodule Revix.Uploaders.ImageTest do
  use ExUnit.Case, async: true

  alias Revix.Uploaders.Image

  @test_jpg Path.expand("../../support/fixtures/test.jpg", __DIR__)

  defp file(path, name), do: %Waffle.File{path: path, file_name: name}

  describe "validate/1" do
    test "accepts a valid JPEG file" do
      assert :ok = Image.validate({file(@test_jpg, "photo.jpg"), nil})
    end

    test "accepts a .jpeg extension" do
      assert :ok = Image.validate({file(@test_jpg, "photo.jpeg"), nil})
    end

    test "rejects a disallowed extension" do
      assert {:error, _} = Image.validate({file(@test_jpg, "photo.bmp"), nil})
    end

    test "rejects a file with wrong magic bytes" do
      tmp = System.tmp_dir!() |> Path.join("not_an_image_#{System.unique_integer()}.jpg")
      File.write!(tmp, "this is not an image")
      on_exit(fn -> File.rm(tmp) end)
      assert {:error, _} = Image.validate({file(tmp, "fake.jpg"), nil})
    end
  end

  describe "filename/2" do
    test "returns the version atom" do
      assert Image.filename(:original, nil) == :original
      assert Image.filename(:thumb, nil) == :thumb
    end
  end

  describe "storage_dir/2" do
    test "returns uploads/images/:id" do
      image = %{id: "abc12345678"}
      assert Image.storage_dir(:original, {nil, image}) == "uploads/images/abc12345678"
    end
  end

  describe "s3_object_headers/2" do
    test "returns content-type header derived from file extension" do
      file = %Waffle.File{path: @test_jpg, file_name: "photo.jpg"}
      assert headers = Image.s3_object_headers(:original, {file, nil})
      assert headers[:content_type] == "image/jpeg"
    end

    test "includes width/height metadata for :large" do
      file = %Waffle.File{path: @test_jpg, file_name: "large.jpg"}
      headers = Image.s3_object_headers(:large, {file, nil})
      assert headers[:meta] == [{"width", "100"}, {"height", "100"}]
    end

    test "includes width/height metadata for :medium" do
      file = %Waffle.File{path: @test_jpg, file_name: "medium.jpg"}
      headers = Image.s3_object_headers(:medium, {file, nil})
      assert headers[:meta] == [{"width", "100"}, {"height", "100"}]
    end

    test "omits dimension metadata for :original" do
      file = %Waffle.File{path: @test_jpg, file_name: "original.jpg"}
      headers = Image.s3_object_headers(:original, {file, nil})
      refute Keyword.has_key?(headers, :meta)
    end

    test "omits dimension metadata for :thumb" do
      file = %Waffle.File{path: @test_jpg, file_name: "thumb.jpg"}
      headers = Image.s3_object_headers(:thumb, {file, nil})
      refute Keyword.has_key?(headers, :meta)
    end

    test "omits dimension metadata when the file cannot be read" do
      file = %Waffle.File{path: "/nonexistent/path.jpg", file_name: "large.jpg"}
      headers = Image.s3_object_headers(:large, {file, nil})
      refute Keyword.has_key?(headers, :meta)
    end

    test "omits dimension metadata when the file is not a valid image" do
      tmp = System.tmp_dir!() |> Path.join("not_an_image_#{System.unique_integer()}.jpg")
      File.write!(tmp, "this is not an image")
      on_exit(fn -> File.rm(tmp) end)

      file = %Waffle.File{path: tmp, file_name: "large.jpg"}
      headers = Image.s3_object_headers(:large, {file, nil})
      refute Keyword.has_key?(headers, :meta)
    end
  end

  describe "transform/2" do
    test ":original is :noaction" do
      assert :noaction = Image.transform(:original, nil)
    end

    test ":large includes -auto-orient before -strip" do
      {:convert, args, :jpg} = Image.transform(:large, nil)
      assert args =~ "-auto-orient -strip"
    end

    test ":medium includes -auto-orient before -strip" do
      {:convert, args, :jpg} = Image.transform(:medium, nil)
      assert args =~ "-auto-orient -strip"
    end

    test ":thumb includes -auto-orient before -strip" do
      {:convert, args, :jpg} = Image.transform(:thumb, nil)
      assert args =~ "-auto-orient -strip"
    end
  end

  describe "public_url/2" do
    test "converts a root-relative URL to an absolute one" do
      image = %{id: "iiiiiiiiiii", file: "large.jpg"}
      url = Image.public_url(image, :large)
      assert url == "http://localhost:4000/uploads/images/iiiiiiiiiii/large.jpg"
    end

    test "keeps a protocol-relative URL as-is" do
      previous_asset_host = Application.get_env(:waffle, :asset_host)
      Application.put_env(:waffle, :asset_host, "//cdn.example.test")

      on_exit(fn ->
        if is_nil(previous_asset_host) do
          Application.delete_env(:waffle, :asset_host)
        else
          Application.put_env(:waffle, :asset_host, previous_asset_host)
        end
      end)

      image = %{id: "iiiiiiiiiii", file: "large.jpg"}
      url = Image.public_url(image, :large)
      assert String.starts_with?(url, "//")
    end

    test "keeps an absolute URL as-is" do
      previous_asset_host = Application.get_env(:waffle, :asset_host)
      Application.put_env(:waffle, :asset_host, "https://cdn.example.test")

      on_exit(fn ->
        if is_nil(previous_asset_host) do
          Application.delete_env(:waffle, :asset_host)
        else
          Application.put_env(:waffle, :asset_host, previous_asset_host)
        end
      end)

      image = %{id: "iiiiiiiiiii", file: "large.jpg"}
      url = Image.public_url(image, :large)
      assert String.starts_with?(url, "https://")
    end
  end
end
