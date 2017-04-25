defmodule Salvo.Server do
  defmodule Stream do
    @moduledoc false
    defstruct port: nil, path: nil, ref: nil

    defimpl Enumerable do
      def reduce(%{ref: ref}, acc, fun) do
        start_fun = fn ->
          ref
        end

        next_fun = fn ref ->
          receive do
            {:recv_frame, ^ref, frame} ->
              {[frame], ref}
          end
        end

        after_fun = fn _ref ->
          :cowboy.stop_listener(ref)
          flush(ref)
        end

        Elixir.Stream.resource(start_fun, next_fun, after_fun).(acc, fun)
      end

      def member?(_stream, _term) do
        {:error, __MODULE__}
      end

      def count(_stream) do
        {:error, __MODULE__}
      end

      @doc false
      defp flush(ref) do
        receive do
          {:recv_frame, ^ref, frame} ->
            IO.inspect {:flush_frame, ref, frame}
            flush(ref)
          {:shutdown, ^ref} ->
            IO.inspect {:flush_shutdown, ref}
            flush(ref)
        after
          0 ->
            :ok
        end
      end

    end
  end

  defmodule Handler do
    @moduledoc false

    def init(req, opts) do
      {:cowboy_websocket, req, opts}
    end

    def websocket_init(state) do
      {:ok, state}
    end

    def websocket_handle(:ping, state) do
      {:reply, :pong, state}
    end
    def websocket_handle(frame, state) do
      send state.pid, {:recv_frame, state.ref, frame}
      {:ok, state}
    end

    def websocket_info({:send_frame, frame}, state) do
      {:reply, frame, state}
    end
    def websocket_info(_msg, state) do
      {:ok, state}
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

      # Write all incoming text frames to a file.
      iex> Salvo.Server.stream!("/websocket", 8080)
      ...> |> Stream.filter(fn
      ...>   {:text, _msg} -> true
      ...>   _ -> false
      ...> end)
      ...> |> Stream.map(fn {:text, msg} -> msg end)
      ...> |> Stream.into(File.stream!("messages.txt"))
      ...> |> Stream.run()
  """
  def stream!(path, port) do
    ref = make_ref()
    dispatch = :cowboy_router.compile(
      _: [{path, Handler, %{pid: self(), ref: ref}}]
    )
    case :cowboy.start_clear(ref, 100, [port: port], %{env: %{dispatch: dispatch}}) do
      {:ok, _} ->
        %Stream{port: port, path: path, ref: ref}
      {:error, e} ->
        raise "Failed starting salvo server with reason: #{inspect e}"
    end
  end

  @doc """
  Broadcast a message to all connected websocket clients

  Note that `Salvo.Server.send!/2` always returns `:ok` and doesn't check if the server is
  alive.
  """
  def send!(%Stream{ref: ref}, frame) do
    for pid <- :ranch.procs(ref, :connections) do
      send pid, {:send_frame, frame}
    end
    :ok
  end

  @doc """
  Gracefully close and shutdown the server
  """
  def shutdown(%Stream{ref: ref}) do
    :cowboy.stop_listener(ref)
  end

  @doc """
  Check if the server is alive and listening for connections.
  """
  def alive?(%Stream{ref: ref}) do
    Enum.any?(:ranch.info(), fn {r, _} -> r == ref end)
  end
end