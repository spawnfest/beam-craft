defmodule BeamCraft.GameServer do
  use GenServer

  @moduledoc """
  GameServer manages the state of players and updating players of changes to the world.

  It provides an api, which is consumed by `BeamCraft.Protocol`, to update a 
  player's state based off of incomming messages, then broadcast out the approprate 
  response to the other connected players.
  """

  @tick_rate 100

  defmodule Player do
    @moduledoc false
    defstruct [:pid, :player_id, :username, :x, :y, :z, :pitch, :yaw, :player_type]
  end


  defmodule PlayerAccount do
    @moduledoc false
    defstruct [:username, :x, :y, :z, :yaw, :pitch, :player_type]
  end

  defmodule State do
    @moduledoc false
    defstruct clients: [], player_id_pool: (for i <- 1..127, do: i), player_table: :player_table
  end

  
  @doc """
  Logs a player into the server.

  This function adds a `BeamCraft.Protocol` pid to the list of,
  connected clients and broadcasts a spawn player message to 
  all clients. The client is given a player id from an internal pool,
  which is used to reference the client in subsequent communications.

  If the same username has connected before, the player will
  be spawned in that position. If not, the player will be
  spawned at the default spawn location,
  given by `BeamCraft.MapServer`.
  """
  def login(username, password) do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:login, username, password})
  end

  @doc """
  Sends a chat message, or processes a command if that chat message begins with a `/`.

  The process calling this must be present in the clients list.

  If the chat message is a regular message, it is broadcast to all connecing clients.
  If it begins with a '/'is can be one of the following chat commands:
    * `/ping` - Replys with pong.
    * `/whereami` - Prints out your current position.
    * `/teleport <x> <y> <z>` - Teleports you to the given point on the map.
    * `/whisper <target> <message>` - Sends a private message to the target player.
  """
  def send_message(message) do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:send_message, message})
  end

  @doc """
  Updates the position of the player.

  The process calling this must be present in the clients list. The change in 
  position is broadcast to all clients.
  """
  def update_position(x, y, z, yaw, pitch) do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:update_position, x, y, z, pitch, yaw})
  end

  @doc """
  Calls `BeamCraft.MapServer.set_block/4` to create a block.

  The process calling this must be present in the clients list. The change 
  is broadcast to all clients.
  """
  def create_block(x, y, z, block_type) do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:create_block, x, y, z, block_type})
  end

  @doc """
  Calls `BeamCraft.MapServer.set_block/4` to create a block.

  The process calling this must be present in the clients list. The change 
  is broadcast to all clients.
  """
  def destroy_block(x, y, z, block_type) do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:destroy_block, x, y, z, block_type})
  end

  @doc """
  Logs a player out of the game.

  The process calling this must be present in the clients list.
  
  Removes a player from the connected clients list, returns the 
  assigned player id to the pool and saves the player's last known
  position.
  """
  def logout() do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:logout})
  end

  @doc """
  Gets the map coordinates and binary representation for `BeamCraft.Protocol`.

  Calls `BeamCraft.MapServer.get_map/0` to retrieve the data nesscary to 
  build the map chunk and map finalize packets, which must be sent to the 
  client before they can move about the game world.
  """
  def get_map_details do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call( server_pid, {:get_map_details})
  end

  @doc """
  Callback for Supervisor.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    :ets.new(:player_table, [:named_table, :ordered_set])
    :erlang.send_after(@tick_rate, self(), :tick)
    {:ok, %State{}}
  end

  # tick game logic
  def handle_info(:tick, state) do
    send_packet_to_all(state, player_ping_msg())

    {:ok, changes} = BeamCraft.MapServer.eval_block_transforms()
    for c <- changes, do: send_packet_to_all(state, c)

    :erlang.send_after(@tick_rate, self(), :tick)
    {:noreply, state}
  end

  # handle login
  def handle_call({:login, username, _password}, {from_pid, _from_ref}, %{player_id_pool: [player_id|rest_pool]} = state) do
    player = case :ets.lookup(state.player_table, {username}) do
      [] ->
        {spawn_x, spawn_y, spawn_z} = BeamCraft.MapServer.get_default_spawn()
        %Player{pid: from_pid,
                     player_id: player_id,
                     username: username,
                     x: spawn_x,
                     y: spawn_y,
                     z: spawn_z,
                     pitch: 0,
                     yaw: 0,
                     player_type: :regular}
      [{{username},%PlayerAccount{} = account}] ->
        %Player{     pid: from_pid,
                     player_id: player_id,
                     username: username,
                     x: account.x,
                     y: account.y,
                     z: account.z,
                     yaw: account.yaw,
                     pitch: account.pitch,
                     player_type: account.player_type}
    end

    # Tell every connected client that a new player has joined
    send_packet_to_all(state, player_to_spawn_msg(player))

    # Tell the newly connecting client about all of the players
    for c <- state.clients, do: send(from_pid, {:send_packet, player_to_spawn_msg(c)})

    server_name = Application.get_env(:beam_craft, :server_name)
    motd = Application.get_env(:beam_craft, :motd)
    reply  = {:ok, server_name, motd, player}
    next_state = %{ state | clients: [player|state.clients], player_id_pool: rest_pool}

    {:reply, reply, next_state}
  end

  def handle_call({:send_message, message}, {from_pid, _from_ref}, state) do
    {sender, _} = player_by_pid(state, from_pid)

    case classify_message(message) do
      {:msg_ping} ->
        send_chat_to_player(state, sender, sender, "pong!")
        {:reply, :ok, state}
      {:msg_whereami} ->
        send_chat_to_player(state, sender, sender, "POS: #{sender.x} #{sender.y} #{sender.z} <#{sender.yaw}, #{sender.pitch}>")
        {:reply, :ok, state}
      {:msg_whisper, user_to, msg} ->
        case player_by_username(state, user_to) do
          {:ok,{recipient,_}} ->
            send_chat_to_player(state, sender, recipient, "#{sender.username} whispers > #{msg}")
            {:reply, :ok, state}
          _ ->
            send_chat_to_player(state, sender, sender, "Can't find player #{user_to} to whisper to!")
            {:reply, :ok, state}
        end
      {:malformed_whisper} ->
        send_chat_to_player(state, sender, sender, "Usage: '/whisper <playername> <message>'")
        {:reply, :ok, state}
      {:msg_teleport, x, y, z} ->
        new_state = teleport_player(state,sender, x,y,z)
        {:reply, :ok, new_state}
      {:malformed_teleport} ->
        send_chat_to_player(state, sender, sender, "Usage: '/teleport <x> <y> <z>'")
        {:reply, :ok, state}
      {:msg_normal, msg} ->
        send_chat_to_players(state, sender, "#{sender.username}> #{msg}")
        {:reply, :ok, state}
      _ ->
        IO.puts("Unhandled player message #{inspect message}")
        {:reply, {:error,:unknown_player_message}, state}
    end
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

    :ets.insert(state.player_table, {{sender.username}, %PlayerAccount{
      username: sender.username,
      x: sender.x, y: sender.y, z: sender.z,
      pitch: sender.pitch, yaw: sender.yaw,
      player_type: sender.player_type
    }})

    new_state = %{state | clients: List.delete_at(state.clients, sender_idx), player_id_pool: [sender.player_id] ++ state.player_id_pool }
    send_packet_to_all(new_state, {:despawn_player, sender.player_id})

    {:reply, :ok, new_state}
  end

  def handle_call({:get_map_details}, {_from_ref, _from_pid}, state) do
    reply = BeamCraft.MapServer.get_map
    {:reply, reply, state}
  end

  # Internal helpers
  defp player_by_pid(state, pid) do
    sender_idx = Enum.find_index(state.clients, fn(c) -> c.pid == pid end)
    sender = Enum.at(state.clients, sender_idx)

    {sender, sender_idx}
  end

  defp teleport_player( state, player, x, y, z) do
    {old_player, player_idx} = player_by_pid(state, player.pid)
    new_player = %{ old_player | x: x, y: y, z: z }
    send_packet_to_player(state, player, player_to_update_position_msg_for_player(new_player))
    send_packet_to_all(state, player_to_update_position_msg(new_player))
    %{ state | clients: List.replace_at(state.clients, player_idx, new_player)}
  end
  
  defp classify_message(msg) do
    parsed = String.split( msg, ~r{\s+}, trim: true)
    case parsed do
      ["/ping"] -> {:msg_ping}
      ["/whereami"]-> {:msg_whereami}
      ["/teleport",rawx,rawy,rawz | _rest] ->
        case [Float.parse(rawx),Float.parse(rawy), Float.parse(rawz)] do
          [{x,_},{y,_},{z,_}] ->
            {:msg_teleport, x, y, z}
          _ ->
            {:malformed_teleport}
        end
      ["/teleport"|_rest]->
        {:malformed_teleport}
      ["/whisper", user_to |_rest] ->
        clean_msg = msg |> String.trim_leading("/whisper #{user_to}")
        {:msg_whisper, user_to, clean_msg}
      ["/whisper" | _rest] ->
        {:malformed_whisper}
      _ -> {:msg_normal, msg}
    end
  end
  
  defp player_by_username(state, username) do
    case Enum.find_index(state.clients, fn(c) -> c.username == username end) do
      nil ->
        {:error, :player_not_found}
      sender_idx->
        {:ok, {Enum.at(state.clients, sender_idx), sender_idx}}
    end
  end

  defp send_chat_to_player(_state, from, to, message) do
    msg = {:message_player, from.player_id, message}
    send(to.pid, {:send_packet, msg})
  end

  defp send_chat_to_players(state, from, message) do
    msg = {:message_player, from.player_id, message}
    send_packet_to_all(state, msg)
  end

  defp send_packet_to_all(state, packet) do
     for c <- state.clients, do: send(c.pid, {:send_packet, packet})
  end

  defp send_packet_to_player(_state, player, packet) do
    send(player.pid, {:send_packet,packet})
  end

  defp player_ping_msg() do
    {:ping}
  end

  defp player_to_spawn_msg(player) do
    {:spawn_player, player.player_id, player.username, player.x, player.y, player.z, player.yaw, player.pitch}
  end

  defp player_to_update_position_msg(player) do
    {:position_player, player.player_id, player.x, player.y, player.z, player.yaw, player.pitch}
  end
  defp player_to_update_position_msg_for_player(player) do
    {:position_player, -1, player.x, player.y, player.z, player.yaw, player.pitch}
  end

  defp teleport_player( state, player, x, y, z) do
    {old_player, player_idx} = player_by_pid(state, player.pid)
    new_player = %{ old_player | x: x, y: y, z: z }
    send_packet_to_player(state, player, player_to_update_position_msg_for_player(new_player))
    send_packet_to_all(state, player_to_update_position_msg(new_player))
    %{ state | clients: List.replace_at(state.clients, player_idx, new_player)}
  end

  defp classify_message(msg) do
    parsed = String.split( msg, ~r{\s+}, trim: true)
    case parsed do
      ["/ping"] -> {:msg_ping}
      ["/whereami"]-> {:msg_whereami}
      ["/teleport",rawx,rawy,rawz | _rest] ->
        case [Float.parse(rawx),Float.parse(rawy), Float.parse(rawz)] do
          [{x,_},{y,_},{z,_}] ->
            {:msg_teleport, x, y, z}
          _ ->
            {:malformed_teleport}
        end
      ["/teleport"| _rest]->
        {:malformed_teleport}
      ["/whisper", user_to | _rest] ->
        clean_msg = msg |> String.trim_leading("/whisper #{user_to}")
        {:msg_whisper, user_to, clean_msg}
      ["/whisper" | _rest] ->
        {:malformed_whisper}
      _ -> {:msg_normal, msg}
    end
  end
end
