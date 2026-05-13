defmodule Revix.Uploaders.AvatarTest do
  use ExUnit.Case, async: true

  alias Revix.Uploaders.Avatar

  @test_jpg Path.expand("../../support/fixtures/test.jpg", __DIR__)

  defp file(path, name), do: %Waffle.File{path: path, file_name: name}

  describe "validate/1" do
    test "accepts a valid JPEG file" do
      assert :ok = Avatar.validate({file(@test_jpg, "photo.jpg"), nil})
    end

    test "accepts a .jpeg extension" do
      assert :ok = Avatar.validate({file(@test_jpg, "photo.jpeg"), nil})
    end

    test "rejects a disallowed extension" do
      assert {:error, _} = Avatar.validate({file(@test_jpg, "photo.bmp"), nil})
    end

    test "rejects a file with wrong magic bytes" do
      tmp = System.tmp_dir!() |> Path.join("not_an_image_#{System.unique_integer()}.jpg")
      File.write!(tmp, "this is not an image")
      on_exit(fn -> File.rm(tmp) end)
      assert {:error, _} = Avatar.validate({file(tmp, "fake.jpg"), nil})
    end
  end

  describe "filename/2" do
    test "returns the version atom" do
      assert Avatar.filename(:thumb, nil) == :thumb
    end
  end

  describe "storage_dir/2" do
    test "returns uploads/people/:id/avatars" do
      scope = %{id: "abc123"}
      assert Avatar.storage_dir(:thumb, {nil, scope}) == "uploads/people/abc123/avatars"
    end
  end

  describe "default_url/2" do
    test "returns identicon path when no avatar is uploaded" do
      scope = %{id: "abc123"}
      assert Avatar.default_url(:thumb, scope) == "/identicon/abc123"
    end
  end
end
