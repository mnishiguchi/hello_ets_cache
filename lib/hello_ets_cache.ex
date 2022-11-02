defmodule HelloEtsCache do
  @moduledoc false

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @spec get(GenServer.name(), any()) :: any()
  def get(server_name, key, default \\ nil) do
    GenServer.call(server_name, {:get, key, default})
  end

  @spec put(GenServer.name(), any(), any()) :: :ok
  def put(server_name, key, value) do
    GenServer.cast(server_name, {:put, key, value})
  end

  @spec delete_all(GenServer.name()) :: :ok
  def delete_all(server_name) do
    GenServer.cast(server_name, :delete_all)
  end

  @impl GenServer
  def init(args) do
    ets_args = args[:ets_args] || []
    cache_name = args[:name]
    cache_ttl = args[:ttl] || :infinity
    get_time_ms = args[:get_time_ms] || fn -> System.monotonic_time(:millisecond) end

    ^cache_name = :ets.new(cache_name, [:set, :named_table, :public] ++ ets_args)

    state = %{
      cache_name: cache_name,
      cache_ttl: cache_ttl,
      get_time_ms: get_time_ms
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:get, key, default}, _from, state) do
    time_now_ms = state.get_time_ms.()

    case :ets.lookup(state.cache_name, key) do
      [] ->
        :telemetry.execute(
          [__MODULE__, :get],
          %{status: :miss},
          %{key: key, cache: state.cache_name}
        )

        {:reply, default, state}

      [{^key, _value, ts, ttl}] when is_integer(ttl) and ts + ttl <= time_now_ms ->
        :telemetry.execute(
          [__MODULE__, :get],
          %{status: :miss},
          %{key: key, cache: state.cache_name}
        )

        {:reply, default, state}

      [{^key, value, _ts, _expire_at}] ->
        :telemetry.execute(
          [__MODULE__, :get],
          %{status: :hit},
          %{key: key, cache: state.cache_name}
        )

        {:reply, value, state}
    end
  end

  @impl GenServer
  def handle_cast({:put, key, value}, state) do
    :telemetry.execute([__MODULE__, :put], %{}, %{key: key, cache: state.cache_name})

    time_now_ms = state.get_time_ms.()

    if state.cache_ttl < 0 do
      raise ArgumentError, "`:ttl` must be greater than 0"
    end

    true = :ets.insert(state.cache_name, {key, value, time_now_ms, state.cache_ttl})

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:delete_all, state) do
    :ets.delete_all_objects(state.cache_name)

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:delete_expired, state) do
    time_now_ms = state.get_time_ms.()

    # See https://github.com/elixir-toniq/mentat/blob/7f1811779ca2dfc80dcb30fe5d70d5809afb3abb/lib/mentat.ex#L228
    match_spec =
      :ets.fun2ms(fn {_key, _value, inserted_at_ms, ttl_ms}
                     when is_integer(ttl_ms) and inserted_at_ms + ttl_ms < time_now_ms ->
        true
      end)

    :ets.select_delete(state.cache_name, match_spec)

    {:noreply, state}
  end
end
