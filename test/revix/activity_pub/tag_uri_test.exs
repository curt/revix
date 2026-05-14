defmodule Revix.ActivityPub.TagUriTest do
  use ExUnit.Case, async: true

  alias Revix.ActivityPub.TagUri

  describe "generate/1" do
    test "returns a tag: URI for the given type" do
      {_id, uri} = TagUri.generate("like")
      assert String.starts_with?(uri, "tag:")
      assert uri =~ "like"
    end

    test "embeds the id in the URI" do
      {id, uri} = TagUri.generate("follow")
      assert uri =~ id
    end

    test "includes the type in the URI" do
      {_id, uri} = TagUri.generate("follow")
      assert uri =~ ":follow:"
    end

    test "returns different values on successive calls" do
      {id1, uri1} = TagUri.generate("like")
      {id2, uri2} = TagUri.generate("like")
      assert id1 != id2
      assert uri1 != uri2
    end
  end
end
