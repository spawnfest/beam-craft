defmodule BeamCraft.GameServer do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    {:ok, %{}}
  end

  # handle login
  def handle_call({username, password}, state}) do
    {:ok, { "server name", "server motd", :usertype_regular }, state}
  end
end
