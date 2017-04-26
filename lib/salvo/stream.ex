defmodule Salvo.Stream do
  defstruct ref: nil, mod: nil

  defimpl Enumerable do
    def reduce(%Salvo.Stream{} = stream, acc, fun) do
      start_fun = fn ->
        {:ok, _} = Registry.register(Salvo, {:stream, stream.ref}, nil)
        stream.ref
      end

      next_fun = fn ref ->
        receive do
          {:recv_frame, ^ref, frame} ->
            {[frame], ref}
          {:halt, ^ref} ->
            {:halt, ref}
        end
      end

      after_fun = fn ref ->
        Registry.unregister(Salvo, {:stream, ref})
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
        {:recv_frame, ^ref, _frame} ->
          flush(ref)
        {:halt, ^ref} ->
          flush(ref)
      after
        0 ->
          :ok
      end
    end
  end

  defimpl Collectable do
    def into(original) do
      {original, fn
        stream, {:cont, x} -> stream.mod.send_frame(stream.ref, x); stream
        stream, :done      -> stream
        _stream, :halt     -> :ok
      end}
    end
  end
end