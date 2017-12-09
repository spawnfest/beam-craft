defmodule BeamCraft.GameServer do
  use GenServer

  @server_name "Beam Craft Server"
  @server_motd "This is a test server!"
  @tick_rate 100

  defmodule Player do
    defstruct [:pid, :player_id, :username, :x, :y, :z, :pitch, :yaw, :player_type]
  end

  defmodule State do
    defstruct clients: [], player_id_pool: (for i <- 1..127, do: i)
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    :erlang.send_after(@tick_rate, self(), :tick)
    {:ok, %State{}}
  end

  defp tick_logic(state) do
    #TODO Tick game logic in here
    state
  end

  # tick game logic
  def handle_info(:tick, state) do
    new_state = tick_logic(state)
    :erlang.send_after(@tick_rate, self(), :tick)
    {:noreply, new_state}
  end

  # handle login
  def handle_call({:login, username, _password}, {from_pid, _from_ref}, %{player_id_pool: [player_id|rest_pool]} = state) do
    {spawn_x, spawn_y, spawn_z} = BeamCraft.MapServer.get_default_spawn()

    player = %Player{pid: from_pid, player_id: player_id, username: username, x: spawn_x, y: spawn_y, z: spawn_z, pitch: 0, yaw: 0, player_type: :regular}

    # Tell every connected client that a new player has joined
    send_packet_to_all(state, player_to_spawn_msg(player))

    # Tell the newly connecting client about all of the players
    for c <- state.clients, do: send(from_pid, {:send_packet, player_to_spawn_msg(c)})

    reply  = {:ok, @server_name, @server_motd, player}
    next_state = %{ state | clients: [player|state.clients], player_id_pool: rest_pool}

    {:reply, reply, next_state}
  end

  def handle_call({:send_message, message}, {from_pid, _from_ref}, state) do
    {sender, _} = player_by_pid(state, from_pid)
    msg = {:message_player, sender.player_id, "#{sender.username}> #{message}"}

    send_packet_to_all(state, msg)

    {:reply, :ok, state}
  end

  def handle_call({:update_position, x, y, z, pitch, yaw}, {from_pid, _from_ref}, state) do
    {old_sender, sender_idx} = player_by_pid(state, from_pid)
    new_sender = %{ old_sender | x: x, y: y, z: z, pitch: pitch, yaw: yaw}

    send_packet_to_all(state, player_to_update_position_msg(new_sender))
    next_state = %{ state | clients: List.replace_at(state.clients, sender_idx, new_sender)}

    {:reply, :ok, next_state}
  end

  def handle_call({:create_block, x, y, z, block_type}, {_from_pid, _from_ref}, state) do
    :ok = BeamCraft.MapServer.set_block(x, y, z, block_type)
    send_packet_to_all(state, {:set_block,  x, y, z, block_type})

    {:reply, :ok, state}
  end

  def handle_call({:destroy_block, x, y, z, _block_type}, {_from_pid, _from_ref}, state) do
    :ok = BeamCraft.MapServer.set_block(x, y, z, 0)
    send_packet_to_all(state, {:set_block,  x, y, z, 0})

    {:reply, :ok, state}
  end

  def handle_call({:logout}, {from_pid, _from_ref}, state) do
    {sender, sender_idx} = player_by_pid(state, from_pid)

    new_state = %{state | clients: List.delete_at(state.clients, sender_idx), player_id_pool: [sender.player_id] ++ state.player_id_pool }
    send_packet_to_all(new_state, {:despawn_player, sender.player_id})

    {:reply, :ok, new_state}
  end

  # fetching map details
  def handle_call({:get_map_details}, {_from_ref, _from_pid}, state) do
    reply = BeamCraft.MapServer.get_map
    {:reply, reply, state}
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
    GenServer.call( server_pid, {:get_map_details})
  end

  # Internal helpers

  defp player_by_pid(state, pid) do
    sender_idx = Enum.find_index(state.clients, fn(c) -> c.pid == pid end)
    sender = Enum.at(state.clients, sender_idx)

    {sender, sender_idx}
  end

  defp player_by_username(state, username) do
    sender_idx = Enum.find_index(state.clients, fn(c) -> c.username == username end)
    sender = Enum.at(state.clients, sender_idx)

    {sender, sender_idx}
  end

  defp send_packet_to_all(state, packet) do
     for c <- state.clients, do: send(c.pid, {:send_packet, packet})
  end

  defp player_to_spawn_msg(player) do
    {:spawn_player, player.player_id, player.username, player.x, player.y, player.z, player.yaw, player.pitch}
  end

  defp player_to_update_position_msg(player) do
    {:position_player, player.player_id, player.x, player.y, player.z, player.yaw, player.pitch}
  end
end
