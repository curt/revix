defmodule Revix.Media.ImageTest do
  use Revix.DataCase

  alias Revix.Media.Image

  describe "changeset/2" do
    test "valid changeset with file and author_uri" do
      upload = %Plug.Upload{
        path: "test/support/fixtures/test.jpg",
        filename: "test.jpg",
        content_type: "image/jpeg"
      }

      changeset =
        Image.changeset(%Image{id: Revix.Ecto.Base58Id.autogenerate()}, %{
          file: upload,
          author_uri: "https://example.com/people/abc"
        })

      assert changeset.valid?
    end

    test "requires author_uri" do
      upload = %Plug.Upload{
        path: "test/support/fixtures/test.jpg",
        filename: "test.jpg",
        content_type: "image/jpeg"
      }

      changeset =
        Image.changeset(%Image{id: Revix.Ecto.Base58Id.autogenerate()}, %{
          file: upload
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).author_uri
    end

    test "requires file" do
      changeset =
        Image.changeset(%Image{id: Revix.Ecto.Base58Id.autogenerate()}, %{
          author_uri: "https://example.com/people/abc"
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).file
    end

    test "converts caption markdown to HTML" do
      upload = %Plug.Upload{
        path: "test/support/fixtures/test.jpg",
        filename: "test.jpg",
        content_type: "image/jpeg"
      }

      changeset =
        Image.changeset(%Image{id: Revix.Ecto.Base58Id.autogenerate()}, %{
          file: upload,
          author_uri: "https://example.com/people/abc",
          caption: "**bold** caption"
        })

      assert changeset.valid?
      html = Ecto.Changeset.get_field(changeset, :caption_html)
      assert html =~ "<strong>bold</strong>"
    end

    test "does not set caption_html when caption is nil" do
      upload = %Plug.Upload{
        path: "test/support/fixtures/test.jpg",
        filename: "test.jpg",
        content_type: "image/jpeg"
      }

      changeset =
        Image.changeset(%Image{id: Revix.Ecto.Base58Id.autogenerate()}, %{
          file: upload,
          author_uri: "https://example.com/people/abc"
        })

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :caption_html)
    end

    test "accepts optional alt text" do
      upload = %Plug.Upload{
        path: "test/support/fixtures/test.jpg",
        filename: "test.jpg",
        content_type: "image/jpeg"
      }

      changeset =
        Image.changeset(%Image{id: Revix.Ecto.Base58Id.autogenerate()}, %{
          file: upload,
          author_uri: "https://example.com/people/abc",
          alt: "A sunset over the ocean"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :alt) == "A sunset over the ocean"
    end

    test "does not cast programmatic fields" do
      upload = %Plug.Upload{
        path: "test/support/fixtures/test.jpg",
        filename: "test.jpg",
        content_type: "image/jpeg"
      }

      changeset =
        Image.changeset(%Image{id: Revix.Ecto.Base58Id.autogenerate()}, %{
          file: upload,
          author_uri: "https://example.com/people/abc",
          id: "injected",
          caption_html: "<script>alert('xss')</script>"
        })

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :id)
      refute Ecto.Changeset.get_change(changeset, :caption_html)
    end
  end

  describe "update_changeset/2" do
    test "updates caption and converts to HTML" do
      changeset =
        Image.update_changeset(%Image{}, %{
          caption: "**bold** caption"
        })

      assert changeset.valid?
      html = Ecto.Changeset.get_field(changeset, :caption_html)
      assert html =~ "<strong>bold</strong>"
    end

    test "updates alt text" do
      changeset =
        Image.update_changeset(%Image{}, %{
          alt: "A beautiful sunset"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :alt) == "A beautiful sunset"
    end

    test "does not require file" do
      changeset = Image.update_changeset(%Image{}, %{})
      assert changeset.valid?
    end

    test "does not cast file or author_uri" do
      changeset =
        Image.update_changeset(%Image{}, %{
          author_uri: "injected",
          content_type: "injected"
        })

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :author_uri)
      refute Ecto.Changeset.get_change(changeset, :content_type)
    end
  end
end
