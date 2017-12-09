defmodule BeamCraft.RanchLink do
  def start_link do
    {:ok, _} = :ranch.start_listener(:beam_craft_listener, 100, :ranch_tcp, [port: 5555], BeamCraft.Protocol, [])
  end
end
