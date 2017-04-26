defmodule Salvo.Server do
  defmodule Handler do
    @moduledoc false

    def init(req, state) do
      {:cowboy_websocket, req, Map.put(state, :path, req.path)}
    end

    def websocket_init(state) do
      {:ok, _} = Registry.register(Salvo, {:server, state.path}, nil)
      {:ok, state}
    end

    def websocket_handle(:ping, state) do
      {:reply, :pong, state}
    end
    def websocket_handle({type, frame}, state) when type in [:text, :binary] do
      Registry.lookup(Salvo, {:stream, state.path})
      |> Enum.each(fn {pid, _} ->
        send pid, {:recv_frame, state.path, frame}
      end)
      {:ok, state}
    end
    def websocket_handle(_unknown, state) do
      {:ok, state}
    end

    def websocket_info({:send_frame, frame}, state) do
      {:reply, frame, state}
    end
    def websocket_info(_msg, state) do
      {:ok, state}
    end
  end

  @doc false
  def start(port) do
    dispatch = :cowboy_router.compile(
      _: [{'/[...]', Handler, %{}}]
    )
    case :cowboy.start_clear(Salvo.Server, 100, [port: port], %{env: %{dispatch: dispatch}}) do
      {:ok, _} ->
        :ok
      {:error, e} ->
        raise "Failed starting salvo server with reason: #{inspect e}"
    end
  end

  @doc """
  Start a streaming websocket server

  Listen for connections at the specified path and port.

  `Salvo.Server.stream!/1` raises an error if setting up the server fails for any reason.

  The returned stream can be used by the `Enum` and `Stream` modules from
  Elixir's standard library. After a stream has finished, it shuts the server
  automatically down, so the stream can not be reused.

  ## Example

      # Write all incoming frames to a file.
      iex> Salvo.Server.stream!("/websocket", 8080)
      ...> |> Stream.into(File.stream!("messages.txt"))
      ...> |> Stream.run()
  """
  def stream!(path) do
    %Salvo.Stream{ref: path, mod: Salvo.Server}
  end

  @doc """
  Send a message to all websocket clients that are connected at `path`
  """
  def send_frame(path, frame, opts \\ []) do
    frame = case {Keyword.get(opts, :type, :text), frame} do
      {_, :close} -> :close
      {type, msg} -> {type, msg}
    end

    Registry.lookup(Salvo, {:server, path})
    |> Enum.each(fn {pid, _} ->
      send pid, {:send_frame, frame}
    end)
  end

  @doc """
  Broadcast a message to all connected websocket clients
  """
  def broadcast(frame, opts \\ []) do
    frame = case {Keyword.get(opts, :type, :text), frame} do
      {_, :close} -> :close
      {type, msg} -> {type, msg}
    end

    :ranch.procs(Salvo.Server, :connections)
    |> Enum.each(fn pid ->
      send pid, {:send_frame, frame}
    end)
  end

  @doc """
  Gracefully close and shutdown the server
  """
  def shutdown(%Salvo.Stream{ref: ref}) do
    Registry.unregister(Salvo.Server, {:stream, ref})
  end

  @doc """
  Check if the server is alive and listening for connections.
  """
  def listening?(%Salvo.Stream{ref: ref}) do
    Enum.any?(:ranch.info(), fn {r, _} -> r == ref end)
  end
end