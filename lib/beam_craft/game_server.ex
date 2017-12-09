defmodule BeamCraft.GameServer do
  use GenServer

  @server_name "Beam Craft Server"
  @server_motd "This is a test server!"

  defmodule Player do
    defstruct [:pid, :player_id, :username, :x, :y, :z, :pitch, :yaw, :player_type]
  end

  defmodule State do
    defstruct clients: [], player_id_pool: (for i <- 1..254, do: i)
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    {:ok, %State{}}
  end

  # handle login
  def handle_call({:login, username, _password}, {from_pid, _from_ref}, %{player_id_pool: [player_id|rest_pool]} = state) do
    player = %Player{pid: from_pid, player_id: player_id, username: username, x: 16.0, y: 1.6, z: 16.0, pitch: 0, yaw: 0, player_type: :regular}

    # Tell every connected client that a new player has joined
    for c <- state.clients, do: send(c.pid, {:send_packet, player_to_spawn_msg(player)})

    # Tell the newly connecting client about all of the players
    for c <- state.clients, do: send(from_pid, {:send_packet, player_to_spawn_msg(c)})

    reply  = {:ok, @server_name, @server_motd, player}
    next_state = %{ state | clients: [player|state.clients], player_id_pool: rest_pool}

    {:reply, reply, next_state}
  end

  def handle_call({:send_message, message}, {from_pid, _from_ref}, state) do
    sender = Enum.find(state.clients, fn(c) -> c.pid == from_pid end)
    msg = {:message, sender.player_id, "#{sender.username}> #{message}"}

    for c <- state.clients, do: send(c.pid, {:send_packet, msg})

    {:reply, :ok, state}
  end

  def handle_call({:update_position, x, y, z, pitch, yaw}, {from_pid, _from_ref}, state) do
    sender_idx = Enum.find_index(state.clients, fn(c) -> c.pid == from_pid end)
    old_sender = Enum.at(state.clients, sender_idx)
    new_sender = %{ old_sender | x: x, y: y, z: z, pitch: pitch, yaw: yaw}

    for c <- state.clients, do: send(c.pid, {:send_packet, player_to_update_position_msg(new_sender)})

    next_state = %{ state | clients: List.replace_at(state.clients, sender_idx, new_sender)}

    {:reply, :ok, next_state}
  end

  def handle_call({:create_block, x, y, z, block_type}, {_from_pid, _from_ref}, state) do
    for c <- state.clients, do: send(c.pid, {:send_packet, {:set_block,  x, y, z, block_type}})

    {:reply, :ok, state}
  end

  def handle_call({:destroy_block, x, y, z, _block_type}, {_from_pid, _from_ref}, state) do
    for c <- state.clients, do: send(c.pid, {:send_packet, {:set_block,  x, y, z, 0}})

    {:reply, :ok, state}
  end

  def handle_call({:logout}, {from_pid, _from_ref}, state) do
    sender_idx = Enum.find_index(state.clients, fn(c) -> c.pid == from_pid end)
    sender = Enum.at(state.clients, sender_idx)

    new_state = %{state | clients: List.delete_at(state.clients, sender_idx), player_id_pool: [sender.player_id] ++ state.player_id_pool }

    for c <- new_state.clients, do: send(c.pid, {:send_packet, {:despawn_player, sender.player_id}})

    {:reply, :ok, new_state}
  end

  def handle_call({:do_get_map_details}, from, state) do
    length = 32
    width = 32
    height = 32
    # This is a large block of water
    map_data = for _ <- 1..(length * width * height), do: 9

    {:reply,
      {length, width, height, map_data},
      state}
  end


  ## client stuff
  def login(username, password) do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:login, username, password})
  end

  def send_message(message) do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:send_message, message})
  end

  def update_position(x, y, z, yaw, pitch) do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:update_position, x, y, z, pitch, yaw})
  end

  def create_block(x, y, z, block_type) do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:create_block, x, y, z, block_type})
  end

  def destroy_block(x, y, z, block_type) do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:destroy_block, x, y, z, block_type})
  end

  def logout() do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:logout})
  end

  def get_map_details do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call( server_pid, {:do_get_map_details})
  end

  defp player_to_spawn_msg(player) do
    {:spawn_player, player.player_id, player.username, player.x, player.y, player.z, player.yaw, player.pitch}
  end

  defp player_to_update_position_msg(player) do
    {:position_player, player.player_id, player.x, player.y, player.z, player.yaw, player.pitch}
  end
end
