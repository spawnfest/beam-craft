defmodule BeamCraft.RanchLink do
  def start_link do
    port = Application.get_env(:beam_craft, :port)
    {:ok, _} = :ranch.start_listener(:beam_craft_listener, 100, :ranch_tcp, [port: port], BeamCraft.Protocol, [])
  end
end
