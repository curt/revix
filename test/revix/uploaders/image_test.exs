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
      file = %Waffle.File{file_name: "photo.jpg"}
      assert [content_type: "image/jpeg"] = Image.s3_object_headers(:original, {file, nil})
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

  describe "acl/2" do
    test ":original is :private" do
      assert :private = Image.acl(:original, nil)
    end

    test "processed versions are :public_read" do
      for version <- [:large, :medium, :thumb] do
        assert :public_read = Image.acl(version, nil)
      end
    end
  end
end
