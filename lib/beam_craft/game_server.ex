defmodule BeamCraft.World do
  @default_width 32
  @default_length 32
  @default_height 32

  defstruct width: @default_width, length: @default_length, height: @default_height, data: <<>>

  def world_init() do
    world = %__MODULE__{
      data: Binary.copy(<<0x09>>, @default_width * @default_length * @default_height)
    }

    {:ok, world, _} = set_block(world, 0,0,0, 6)
    # fill stone (height = 0 to 19)
    world = Enum.reduce(
              generate_cube_coords(0,0,0,@default_width,@default_length,20),
              world,
              fn({x,y,z},world)->
                {:ok, new_world, _} =set_block(world,x,y,z, 1)
                new_world
              end)

    # fill dirt (height = 20 to 24)
    world = Enum.reduce(
              generate_cube_coords(0,0,20,@default_width,@default_length,4),
              world,
              fn({x,y,z},world)->
                {:ok, new_world, _} =set_block(world,x,y,z, 3)
                new_world
              end)

    # fill grass (height = 25)
    world = Enum.reduce(
              generate_cube_coords(0,0,24,@default_width,@default_length,1),
              world,
              fn({x,y,z},world)->
                {:ok, new_world, _} =set_block(world,x,y,z, 2)
                new_world
              end)

    # add foiliage (height = 26)
    world
  end

  def generate_cube_coords(xoff,yoff,zoff,l,w,h) do
    for ycoord <-yoff..yoff+w-1,
        zcoord <-zoff..zoff+h-1,
        xcoord <-xoff..xoff+l-1,
         do:
          {xcoord,ycoord,zcoord}
  end

  defp set_binary_at(binary, position, value) do
    case Binary.split_at(binary, position) do
      {f,""} -> # the last or clamped position
        <<f::binary, value::size(8)>>
      {f,<<first::size(8),rest::binary>>} ->
        <<f::binary, value::size(8), rest::binary>>
    end
  end

  def set_block( world, x, y, z, t) do
    if is_valid_block_position?( world, x, y, z ) do
      idx = get_index_for_block_position(world.width, world.length, world.height, x,y,z)
      old_type = Binary.at(world.data, idx)
      new_world = set_binary_at(world.data,idx, t)
      {:ok, %{world|data: new_world}, old_type }
    else
      {:error, :invalid_block_position}
    end
  end

  def get_block( world, x, y, z) do
    if is_valid_block_position?( world, x, y, z ) do
      block_type = Binary.at(world.data,
                             get_index_for_block_position(world.width,
                                                          world.length,
                                                          world.height,
                                                          x,y,z))
      {:ok, block_type}
    else
      {:error, :invalid_block_position}
    end
  end

  @doc """
  Gets the offset (in bytes) of the block for a given block at x,y,z in a world
  of size w,l,h.

  *This must be protected by `is_valid_block_position?` or simlar.*
  """
  defp get_index_for_block_position( w, l, h, x, y, z) do
    x + y* (w) + z *(w*l)
  end

  def is_valid_block_position?( %__MODULE__{data: data, width: w, height: h, length: l},
                                 x, y, z)
    when is_integer(x) and is_integer(y) and is_integer(z)
    and x >= 0 and y >= 0 and z >= 0
  do
    x < w and y < h and z < l
  end
  def is_valid_block_position?( _world, _x, _y, _z), do: false

end

defmodule BeamCraft.GameServer do
  @default_width 32
  @default_length 32
  @default_height 32

  use GenServer
  alias BeamCraft.World

  @server_name "Beam Craft Server"
  @server_motd "This is a test server!"

  defmodule Player do
    defstruct [:pid, :player_id, :username, :x, :y, :z, :pitch, :yaw, :player_type]
  end

  defmodule State do
    alias BeamCraft.GameServer
    defstruct clients: [], player_id_pool: (for i <- 1..127, do: i),
              world: World.world_init()
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    {:ok, %State{}}
  end

  def pick_spawn_point() do
    {1.0,@default_height-1.6,1.0}
  end

  # handle login
  def handle_call({:login, username, _password}, {from_pid, _from_ref}, %{player_id_pool: [player_id|rest_pool]} = state) do
    {spawnx,spawny,spawnz} = pick_spawn_point()
    player = %Player{pid: from_pid, player_id: player_id, username: username, x: spawnx, y: spawny, z: spawnz, pitch: 0, yaw: 0, player_type: :regular}

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
    send_packet_to_all(state, {:set_block,  x, y, z, block_type})

    {:reply, :ok, state}
  end

  def handle_call({:destroy_block, x, y, z, _block_type}, {_from_pid, _from_ref}, state) do
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
    world = state.world
    {:reply,
      {world.length, world.width, world.height, world.data},
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
