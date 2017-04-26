defmodule Salvo.Client do
  defmodule Handler do
    @moduledoc false
    use GenServer

    @keepalive_interval 10_000

    def start_link(url) do
      GenServer.start_link(__MODULE__, url)
    end

    def init(url) do
      {:ok, _} = Registry.register(Salvo, {:client, url}, nil)
      uri = URI.parse(url)
      with {:ok, pid} <- :gun.open(String.to_charlist(uri.host), uri.port, %{protocols: [:http]}),
           {:ok, _} <- :gun.await_up(pid)
      do
        _ = :gun.ws_upgrade(pid, uri.path)
        mref = Process.monitor(pid)
        Process.send_after(self(), :pingpong, @keepalive_interval)
        {:ok, %{pid: pid, mref: mref, url: url, path: uri.path, buffer: [], upgraded?: false}}
      else
        {:error, e} ->
          {:stop, e}
      end
    end

    def handle_call(:connected?, _from, state) do
      {:reply, state.upgraded?, state}
    end

    def handle_cast({:send_frame, frame}, state) do
      if state.upgraded? do
        :gun.ws_send(state.pid, frame)
        {:noreply, state}
      else
        {:noreply, %{state|buffer: [frame | state.buffer]}}
      end
    end
    def handle_cast(:shutdown, state) do
      send_to_stream(state, :halt)
      :gun.shutdown(state.pid)
      {:stop, :normal, state}
    end

    def handle_info(:pingpong, state) do
      :gun.ws_send(state.pid, :ping)
      Process.send_after(self(), :pingpong, @keepalive_interval)
      {:noreply, state}
    end
    def handle_info({:gun_ws_upgrade, _pid, :ok, _headers}, state) do
      Enum.each(state.buffer, &:gun.ws_send(state.pid, &1))
      {:noreply, %{state|upgraded?: true, buffer: []}}
    end
    def handle_info({:gun_response, _pid, _ref, _fin, status, _headers}, state) do
      send_to_stream(state, :halt)
      exit({:http_error, status})
    end
    def handle_info({:gun_ws, _pid, :pong}, state) do
      {:noreply, state}
    end
    def handle_info({:gun_ws, _pid, :close}, state) do
      send_to_stream(state, :halt)
      {:stop, :normal, state}
    end
    def handle_info({:gun_ws, _pid, {type, frame}}, state) when type in [:text, :binary] do
      send_to_stream(state, frame)
      {:noreply, state}
    end
    def handle_info({:gun_ws, _pid, _unknown}, state) do
      {:noreply, state}
    end
    def handle_info({:gun_down, _pid, _, _, _, _}, state) do
      {:noreply, %{state|upgraded?: false}}
    end
    def handle_info({:gun_up, pid, _}, state) do
      _ = :gun.ws_upgrade(pid, state.path)
      {:noreply, state}
    end
    def handle_info({:gun_error, _pid, reason}, state) do
      send_to_stream(state, :halt)
      exit({:gun_error, reason})
    end
    def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
      if ref == state.mref do
        send_to_stream(state, :halt)
        if reason == :normal do
          {:stop, :normal, state}
        else
          exit({:gun_error, reason})
        end
      else
        {:noreply, state}
      end
    end

    defp send_to_stream(state, :halt) do
      Registry.lookup(Salvo, {:stream, state.url})
      |> Enum.each(fn {pid, _} -> send pid, :halt end)
    end
    defp send_to_stream(state, data) do
      Registry.lookup(Salvo, {:stream, state.url})
      |> Enum.each(fn {pid, _} -> send pid, {:recv_frame, state.url, data} end)
    end
  end

  @doc """
  Start a streaming websocket client

  Connect to a websocket server at the provided url. The schema part of the url is ignored as
  the client currently always tries to connect via http and asks the server for an upgrade to
  a websocket.

  `Salvo.Client.stream!/1` raises an error if the connection fails for any reason.

  The returned stream can be used by the `Enum` and `Stream` modules from
  Elixir's standard library. After a stream has finished, it closes the client
  automatically, so the stream can not be reused.

  ## Example

      # Take the first 10 messages and print them to the console
      iex> Salvo.Client.stream!("http://127.0.0.1:8080/websocket")
      ...> |> Stream.take(10)
      ...> |> Enum.each(&IO.inspect(&1))
  """
  def stream!(url) do
    case Handler.start_link(url) do
      {:ok, _} ->
        %Salvo.Stream{ref: url, mod: __MODULE__}
      {:error, e} ->
        raise "Failed starting salvo client with reason: #{inspect e}"
    end
  end

  @doc """
  Send a message to a websocket server

  Note that `Salvo.Client.send!/2` always returns `:ok` and doesn't check if the client is
  connected or even alive.
  """
  def send_frame(url, data, opts \\ []) do
    case Registry.lookup(Salvo, {:client, url}) do
      [{pid, _}] ->
        type = Keyword.get(opts, :type, :text)
        GenServer.cast(pid, {:send_frame, {type, data}})
      [] ->
        :ok
    end
  end

  @doc """
  Gracefully close and shutdown the client
  """
  def shutdown(%Salvo.Stream{ref: ref}) do
    case Registry.lookup(Salvo, {:client, ref}) do
      [{pid, _}] ->
        GenServer.cast(pid, :shutdown)
      _ ->
        :ok
    end
  end

  @doc """
  Check if the client is alive and connected
  """
  def connected?(%Salvo.Stream{ref: pid}) do
    Process.alive?(pid) and GenServer.call(pid, :connected?)
  end
end