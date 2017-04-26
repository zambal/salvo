defmodule Salvo.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(Registry, [:duplicate, Salvo])
    ]

    server_config = Application.get_env(:salvo, :server) |> List.wrap()
    auto_start = Keyword.get(server_config, :auto_start, true)
    if auto_start do
      port = Keyword.get(server_config, :port, 8080)
      :ok = Salvo.Server.start(port)
    end

    Supervisor.start_link(children, strategy: :one_for_one, name: Salvo.Supervisor)
  end
end
