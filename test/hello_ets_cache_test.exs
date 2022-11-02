defmodule HelloEtsCacheTest do
  use ExUnit.Case
  doctest HelloEtsCache

  test "TODO" do
    HelloEtsCache.start_link(name: :test_ets, ttl: 1_000)

    assert HelloEtsCache.get(:test_ets, :a) |> is_nil()

    HelloEtsCache.put(:test_ets, :a, 1)
    assert HelloEtsCache.get(:test_ets, :a) == 1

    Process.sleep(1000)

    assert HelloEtsCache.get(:test_ets, :a) |> is_nil()
  end
end
