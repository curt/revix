defmodule Revix.MediaTest do
  use Revix.DataCase

  alias Revix.Media

  import Revix.MediaFixtures
  import Revix.EntriesFixtures

  describe "create_image/1" do
    test "creates an image with valid attrs" do
      upload = %Plug.Upload{
        path: "test/support/fixtures/test.jpg",
        filename: "photo.jpg",
        content_type: "image/jpeg"
      }

      attrs = %{
        file: upload,
        author_uri: "https://example.com/people/abc",
        content_type: "image/jpeg",
        original_filename: "photo.jpg"
      }

      assert {:ok, image} = Media.create_image(attrs)
      assert image.author_uri == "https://example.com/people/abc"
      assert image.content_type == "image/jpeg"
      assert image.original_filename == "photo.jpg"
      assert image.file
    end

    test "returns error without required fields" do
      assert {:error, changeset} = Media.create_image(%{})
      refute changeset.valid?
    end
  end

  describe "get_image/1" do
    test "returns image when it exists" do
      image = image_fixture()
      assert {:ok, found} = Media.get_image(image.id)
      assert found.id == image.id
    end

    test "returns error when image does not exist" do
      assert {:error, :not_found} = Media.get_image(Revix.Ecto.Base58Id.autogenerate())
    end
  end

  describe "attach_image_to_entry/3" do
    test "creates a join record" do
      image = image_fixture()
      entry = checkin_fixture()

      assert {:ok, entry_image} = Media.attach_image_to_entry(entry.id, image.id, 0)
      assert entry_image.entry_id == entry.id
      assert entry_image.image_id == image.id
      assert entry_image.position == 0
    end
  end

  describe "get_images_for_entry/1" do
    test "returns images ordered by position" do
      entry = checkin_fixture()
      image1 = image_fixture()
      image2 = image_fixture()
      image3 = image_fixture()

      {:ok, _} = Media.attach_image_to_entry(entry.id, image3.id, 2)
      {:ok, _} = Media.attach_image_to_entry(entry.id, image1.id, 0)
      {:ok, _} = Media.attach_image_to_entry(entry.id, image2.id, 1)

      images = Media.get_images_for_entry(entry.id)
      assert length(images) == 3
      assert Enum.map(images, & &1.id) == [image1.id, image2.id, image3.id]
    end

    test "returns empty list when no images are attached" do
      entry = checkin_fixture()
      assert Media.get_images_for_entry(entry.id) == []
    end
  end

  describe "delete_image/1" do
    test "deletes the image record" do
      image = image_fixture()
      assert {:ok, _} = Media.delete_image(image)
      assert {:error, :not_found} = Media.get_image(image.id)
    end
  end

  describe "update_image/2" do
    test "updates caption and converts to HTML" do
      image = image_fixture()
      assert {:ok, updated} = Media.update_image(image, %{caption: "**bold**"})
      assert updated.caption == "**bold**"
      assert updated.caption_html =~ "<strong>bold</strong>"
    end

    test "updates alt text" do
      image = image_fixture()
      assert {:ok, updated} = Media.update_image(image, %{alt: "A sunset"})
      assert updated.alt == "A sunset"
    end
  end

  describe "update_entry_image_position/3" do
    test "updates the position of an entry image" do
      entry = checkin_fixture()
      image = image_fixture()
      {:ok, _} = Media.attach_image_to_entry(entry.id, image.id, 0)

      {1, _} = Media.update_entry_image_position(entry.id, image.id, 5)

      [updated] = Media.get_images_for_entry(entry.id)
      assert updated.id == image.id
    end
  end

  describe "create_and_attach_images/3" do
    test "returns {:ok, []} for a non-list uploads value" do
      entry = checkin_fixture()

      assert {:ok, []} =
               Media.create_and_attach_images(entry.id, "https://example.com/people/x", nil)
    end

    test "returns {:ok, []} for an empty list" do
      entry = checkin_fixture()

      assert {:ok, []} =
               Media.create_and_attach_images(entry.id, "https://example.com/people/x", [])
    end

    test "creates and attaches each upload" do
      entry = checkin_fixture()

      upload = %Plug.Upload{
        path: "test/support/fixtures/test.jpg",
        filename: "photo.jpg",
        content_type: "image/jpeg"
      }

      assert {:ok, images} =
               Media.create_and_attach_images(entry.id, "https://example.com/people/x", [upload])

      assert length(images) == 1
      assert hd(images).content_type == "image/jpeg"
      assert length(Media.get_images_for_entry(entry.id)) == 1
    end
  end

  describe "retransform_images_for_entry/1" do
    test "re-processes stored originals and refreshes the cache-busting timestamp" do
      entry = checkin_fixture()

      upload = %Plug.Upload{
        path: "test/support/fixtures/test.jpg",
        filename: "photo.jpg",
        content_type: "image/jpeg"
      }

      {:ok, [image]} =
        Media.create_and_attach_images(entry.id, "https://example.com/people/abc", [upload])

      image
      |> Ecto.Changeset.change(
        file: %{file_name: image.file.file_name, updated_at: ~N[2020-01-01 00:00:00]}
      )
      |> Revix.Repo.update!()

      :ok = Media.retransform_images_for_entry(entry.id)

      {:ok, refreshed} = Media.get_image(image.id)
      assert NaiveDateTime.compare(refreshed.file.updated_at, ~N[2020-01-01 00:00:00]) == :gt
    end

    test "returns :ok when entry has no images" do
      entry = checkin_fixture()
      assert :ok = Media.retransform_images_for_entry(entry.id)
    end
  end

  describe "remove_image_from_entry/2" do
    test "removes the join record and deletes orphaned image" do
      entry = checkin_fixture()
      image = image_fixture()
      {:ok, _} = Media.attach_image_to_entry(entry.id, image.id, 0)

      assert :ok = Media.remove_image_from_entry(entry.id, image.id)
      assert Media.get_images_for_entry(entry.id) == []
      assert {:error, :not_found} = Media.get_image(image.id)
    end

    test "does not delete image if it is attached to another entry" do
      entry1 = checkin_fixture()
      entry2 = checkin_fixture()
      image = image_fixture()
      {:ok, _} = Media.attach_image_to_entry(entry1.id, image.id, 0)
      {:ok, _} = Media.attach_image_to_entry(entry2.id, image.id, 0)

      assert :ok = Media.remove_image_from_entry(entry1.id, image.id)
      assert Media.get_images_for_entry(entry1.id) == []
      assert {:ok, _} = Media.get_image(image.id)
    end

    test "returns ok when join record does not exist" do
      entry = checkin_fixture()
      assert :ok = Media.remove_image_from_entry(entry.id, Revix.Ecto.Base58Id.autogenerate())
    end
  end
end
