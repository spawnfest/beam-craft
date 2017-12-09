defmodule BeamCraft.GameServer do
  use GenServer

  @server_name "Beam Craft Server"
  @server_motd "This is a test server!"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    {:ok, %{clients: []}}
  end

  # handle login
  def handle_call({_username, _password}, from, state) do
    {:reply,
      { @server_name, @server_motd, :usertype_regular },
      %{state|clients: [from|state.clients]}
  }
  end

  ## client stuff
  def login(username, password) do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call( server_pid, {username, password})
  end

  # TODO: Back this against the state of the game world
  def get_map_details do
    length = 32
    width = 32
    height = 32
    # This is a large block of water
    map_data = for _ <- 1..(length * width * height), do: 9
    
    {length, width, height, map_data}
  end
end
