defmodule HelloEtsCache do
  use GenServer

  require Ex2ms

  # キャッシュストアのインスタンスを生成する
  def start_link(opts) do
    server_name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: server_name)
  end

  # キャッシュストアを削除する
  @spec stop(atom | pid | {atom, any} | {:via, atom, any}) :: :ok
  def stop(cache_name) do
    GenServer.stop(cache_name)
  end

  # キャッシュストアから有効な値を取得
  def get(cache_name, key, default \\ nil) do
    GenServer.call(cache_name, {:get, key, default})
  end

  # キャッシュストアから全ての有効な値を取得
  @spec get_all(atom | pid | {atom, any} | {:via, atom, any}) :: any
  def get_all(cache_name) do
    GenServer.call(cache_name, :get_all)
  end

  # キャッシュストアに値を挿入
  def put(cache_name, key, value) do
    GenServer.cast(cache_name, {:put, key, value})
  end

  # キャッシュストアから全ての値を削除
  def delete_all(cache_name) do
    GenServer.cast(cache_name, :delete_all)
  end

  # キャッシュストア内部のリストを取得
  def entries(cache_name) do
    :ets.select(
      cache_name,
      Ex2ms.fun do
        {k, v, ttl} -> {k, v, ttl}
      end
    )
  end

  @impl true
  def init(args) do
    cache_name = args[:name]
    cache_ttl = args[:ttl] || :infinity
    cleanup_interval = args[:cleanup_interval] || :timer.minutes(60)

    # ETSテーブルを生成
    ^cache_name = :ets.new(cache_name, [:set, :named_table, :public])

    # キャッシュの名前とTTLを覚えておく
    state = %{
      cache_name: cache_name,
      cache_ttl: cache_ttl,
      cleanup_interval: cleanup_interval
    }

    # すぐ呼び出し元にプロセスIDを返し、handle_continueで非同期に他の処理をする
    {:ok, state, {:continue, :after_init}}
  end

  @impl true
  def handle_continue(:after_init, state) do
    Process.send_after(self(), :delete_expired, state.cleanup_interval)

    {:noreply, state}
  end

  @impl true
  def handle_call({:get, key, default}, _from, state) do
    time_now_ms = System.monotonic_time(:millisecond)

    reply =
      case :ets.lookup(state.cache_name, key) do
        # 値が見つからなかった場合、デフォルトの値を返す
        [] ->
          default

        # 値が見つかったが期限切れの場合、デフォルトの値を返す
        [{^key, _value, inserted_at_ms}]
        when is_integer(state.cache_ttl) and inserted_at_ms + state.cache_ttl <= time_now_ms ->
          default

        # 見つかった値を返す
        [{^key, value, _inserted_at_ms}] ->
          value
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call(:get_all, _from, state) do
    reply = do_get_all(state)

    {:reply, reply, state}
  end

  @impl true
  def handle_cast({:put, key, value}, state) do
    inserted_at_ms = System.monotonic_time(:millisecond)

    # キーと値のペアを時刻（マイクロ秒）と共に挿入
    true = :ets.insert(state.cache_name, {key, value, inserted_at_ms})

    {:noreply, state}
  end

  @impl true
  def handle_cast(:delete_all, state) do
    :ets.delete_all_objects(state.cache_name)

    {:noreply, state}
  end

  @impl true
  def handle_info(:delete_expired, state) do
    # 次回のキャッシュのクリアのタイマーをセット
    Process.send_after(self(), :delete_expired, state.cleanup_interval)

    # 今キャッシュのクリアを実施
    do_delete_expired(state)

    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    # GenServerが停止したら、紐づいているETSインスタンスも削除する方針
    :ets.delete(state.cache_name)
    reason
  end

  defp do_get_all(%{cache_name: cache_name, cache_ttl: cache_ttl}) do
    time_now_ms = System.monotonic_time(:millisecond)

    :ets.select(
      cache_name,
      Ex2ms.fun do
        {key, value, inserted_at_ms}
        when is_integer(^cache_ttl) and inserted_at_ms + ^cache_ttl >= ^time_now_ms ->
          {key, value}
      end
    )
  end

  defp do_delete_expired(%{cache_name: cache_name, cache_ttl: cache_ttl}) do
    time_now_ms = System.monotonic_time(:millisecond)

    :ets.select_delete(
      cache_name,
      Ex2ms.fun do
        {_key, _value, inserted_at_ms}
        when is_integer(^cache_ttl) and inserted_at_ms + ^cache_ttl < ^time_now_ms ->
          true
      end
    )
  end
end
