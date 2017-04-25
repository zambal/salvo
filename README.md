# Salvo

Experimental interface for a websocket client and server.

The client is powered by [gun](https://github.com/ninenines/gun) and
the server by [cowboy](https://github.com/ninenines/cowboy).

Messages received by both the client and server are emitted as Elixir [streams](https://hexdocs.pm/elixir/Stream.html).

An example says more than a thousand as the saying goes, so here's one:

```elixir
# Spawn a process and start a streaming server in it that prints all incoming frames to the console.
iex> spawn fn ->
...> Salvo.Server.stream!("/websocket", 8080)
...> |> Enum.each(&IO.inspect(&1))
...> end
#PID<0.178.0>

# Start a streaming client and send a frame
iex> client = Salvo.Client.stream!("http://127.0.0.1:8080/websocket")
%Salvo.Client.Stream{pid: #PID<0.284.0>, url: "http://127.0.0.1:8080/websocket"}
iex> Salvo.Client.send!(client, {:text, "abcd"})
:ok
{:text, "abcd"}
```

See the module documentation for more info and examples.

## Installation

```elixir
def deps do
  [{:salvo, "~> 0.1.0"}]
end
```
