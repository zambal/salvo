# Salvo

Experimental interface for a websocket client and server.

The client is powered by [gun](https://github.com/ninenines/gun) and
the server by [cowboy](https://github.com/ninenines/cowboy).

Messages received by both the client and server are emitted as Elixir [streams](https://hexdocs.pm/elixir/Stream.html).
Both the client and server also implement the `Collectable` protocol, so they can be used with `Enum.into/2`.

An example says more than a thousand as the saying goes, so here's one:

```elixir
# Start a streaming server that listens on port 8080
iex> server = Salvo.Server.stream!("/websocket", 8080)
%Salvo.Server.Stream{path: "/websocket", port: 8080, ref: #Reference<0.0.1.789>}

# Spawn a process and start a streaming client in it that prints all incoming frames to the console.
iex> spawn fn ->
...> Salvo.Client.stream!("http://127.0.0.1:8080/websocket")
...> |> Enum.each(&IO.inspect(&1))
...> end
#PID<0.178.0>

# Send a frame from the server to the client
iex> Salvo.Server.send!(server, "abcd")
:ok
"abcd"
```
And another example that uses streams and collectables to push a file from the server on one node to the client on another node:

```elixir
# node 1
iex> server = Salvo.Server.stream!("/websocket", 8080)

# node 2
iex> client = Salvo.Client.stream!("http://127.0.0.1:8080/websocket")
iex> Stream.into(client, File.stream!("README.bak")) |> Stream.run()

# node 1
iex> File.stream!("README.md") |> Stream.into(server) |> Stream.run()

# Tell the client to close it's connection
iex> Salvo.Server.send!(server, :close)
```

See the module documentation for more info and examples.
