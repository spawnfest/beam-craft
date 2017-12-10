defmodule BeamCraft.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      {BeamCraft.MapServer, [name: BeamCraft.MapServer]},
      {BeamCraft.GameServer, [name: BeamCraft.GameServer]},
      worker(BeamCraft.RanchLink, [])
    ]

    opts = [strategy: :one_for_one, name: BeamCraft.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
