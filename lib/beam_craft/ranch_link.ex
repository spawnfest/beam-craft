defmodule BeamCraft.RanchLink do
  @moduledoc """
  Wrapper module to get ranch into Elixir's supervisor.
  """

  @doc """
  Starts the ranch listener, listening on the port set in the application environment.
  """
  def start_link do
    port = Application.get_env(:beam_craft, :port)
    {:ok, _} = :ranch.start_listener(:beam_craft_listener, 100, :ranch_tcp, [port: port], BeamCraft.Protocol, [])
  end
end
