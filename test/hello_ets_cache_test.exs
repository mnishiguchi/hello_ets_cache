defmodule HelloEtsCacheTest do
  use ExUnit.Case
  doctest HelloEtsCache

  test "greets the world" do
    assert HelloEtsCache.hello() == :world
  end
end
