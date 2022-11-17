defmodule HelloEtsCacheTest do
  use ExUnit.Case
  doctest HelloEtsCache

  test "cache for 1 second" do
    {:ok, _} = HelloEtsCache.start_link(name: :test_ets, ttl: 500)

    assert HelloEtsCache.get(:test_ets, :a) |> is_nil()

    HelloEtsCache.put(:test_ets, :a, 1)
    assert HelloEtsCache.get(:test_ets, :a) == 1

    Process.sleep(500)

    assert HelloEtsCache.get(:test_ets, :a) |> is_nil()
  end

  test "cache forever" do
    {:ok, _} = HelloEtsCache.start_link(name: :test_ets, ttl: :infinity)

    HelloEtsCache.put(:test_ets, :a, 1)
    assert HelloEtsCache.get(:test_ets, :a) == 1

    Process.sleep(500)

    assert HelloEtsCache.get(:test_ets, :a) == 1
  end

  test "delete_all" do
    {:ok, _} = HelloEtsCache.start_link(name: :test_ets, ttl: :infinity)

    HelloEtsCache.put(:test_ets, :a, 1)
    HelloEtsCache.put(:test_ets, :b, 2)
    HelloEtsCache.put(:test_ets, :c, 3)

    assert HelloEtsCache.get(:test_ets, :a) == 1
    assert HelloEtsCache.get(:test_ets, :b) == 2
    assert HelloEtsCache.get(:test_ets, :c) == 3

    HelloEtsCache.delete_all(:test_ets)

    assert HelloEtsCache.get(:test_ets, :a) |> is_nil()
    assert HelloEtsCache.get(:test_ets, :b) |> is_nil()
    assert HelloEtsCache.get(:test_ets, :c) |> is_nil()
  end

  test "entries" do
    {:ok, _} = HelloEtsCache.start_link(name: :test_ets, ttl: 3, cleanup_interval: 500)

    # Insert some records
    HelloEtsCache.put(:test_ets, :a, 1)
    HelloEtsCache.put(:test_ets, :b, 2)
    HelloEtsCache.put(:test_ets, :c, 3)

    # The records are accessible before expired
    assert HelloEtsCache.get(:test_ets, :a) == 1
    assert HelloEtsCache.get(:test_ets, :b) == 2
    assert HelloEtsCache.get(:test_ets, :c) == 3
    assert [{:c, 3}, {:b, 2}, {:a, 1}] == HelloEtsCache.entries(:test_ets)

    Process.sleep(3)

    # The records are not accessible after expired
    assert HelloEtsCache.get(:test_ets, :a) |> is_nil()
    assert HelloEtsCache.get(:test_ets, :b) |> is_nil()
    assert HelloEtsCache.get(:test_ets, :c) |> is_nil()
    assert [{:c, 3}, {:b, 2}, {:a, 1}] == HelloEtsCache.entries(:test_ets)

    Process.sleep(500)

    # Internal entries gets deleted after cleanup interval elapsed
    assert HelloEtsCache.entries(:test_ets) |> Enum.empty?()
  end
end
