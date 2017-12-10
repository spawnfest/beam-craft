defmodule BeamCraft.MapServer do
  use GenServer

  defmodule State do
    defstruct map_table: :map_table, length: 128, width: 128, height: 32
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(_opts) do
    map_table = :ets.new(:map_table, [:named_table])
    state = %State{map_table: map_table}
    generate_flat_map(state)
    {:ok, state}
  end

  def handle_call({:get_map}, _from, state) do
    map_cells = Enum.sort_by(:ets.match(state.map_table, {:'$1', :'$2'}), fn([{x,y,z}, _]) -> {y,z,x} end)
    map_data = Enum.reduce(map_cells, <<>>, fn([_, v], acc) -> acc <> << v :: unsigned-big-integer-size(8) >> end)

    {:reply, {state.length, state.width, state.height, map_data}, state}
  end

  def handle_call({:get_default_spawn}, _from, state) do
    {:reply, {16, 16 + 1.6, 16}, state}
  end

  def handle_call({:set_block, x, y, z, block_type}, _from, state) do
    :ets.insert(state.map_table, {{x,y,z}, block_type})

    {:reply, :ok, state}
  end

  def handle_call({:get_blocks_by_type, block_type}, _from, state) do
    blocks = :ets.match(state.map_table, {:'$1', block_type})
    {:reply, blocks, state}
  end

  def adjacent_blocks( x, y, z, l, h, d) do
    [
      {x-1,y,z},{x+1,y,z},
      {x,y-1,z},{x,y+1,z},
      {x,y,z-1},{x,y,z+1},
    ]
    |> Enum.filter( fn({x,y,z})->
      x >= 0 and x < l
      and y >= 0 and y < h
      and z >= 0 and z < d
    end)
  end

  def handle_call({:get_blocks_adjacent_to_type, block_type}, _from, state) do
    blocks = :ets.match(state.map_table, {:'$1', block_type})
      |> Enum.flat_map(fn(x)->x end)

    #IO.puts "Blocks of type #{block_type}, found #{blocks |> length}"

    #IO.puts "BOCKS #{inspect blocks}"

    raw_adj_blocks = for {x,y,z} <- blocks do
      adjacent_blocks( x,y,z, state.width, state.height, state.length )
    end

#    IO.puts "BOCKS #{inspect raw_adj_blocks}"

    adj_blocks =  raw_adj_blocks |> Enum.flat_map(fn(x)->x end) |> Enum.uniq()

    {:reply, adj_blocks, state}
  end

  def get_blocks_by_type( type ) do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:get_blocks_by_type, type})
  end

  def get_blocks_adjacent_to_type( type ) do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:get_blocks_adjacent_to_type, type})
  end

  def get_map() do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:get_map})
  end

  def get_default_spawn() do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:get_default_spawn})
  end

  def set_block(x, y, z, block_type) do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:set_block, x, y, z, block_type})
  end

  defp generate_flat_map(state) do
    # Fill the map with air
    for x <- 0..(state.width - 1), y <- 0..(state.height - 1), z <- 0..(state.length - 1), do: :ets.insert(state.map_table, {{x,y,z}, 0})

    for x <- 0..(state.width - 1), y <- 0..13, z <- 0..(state.length - 1), do: :ets.insert(state.map_table, {{x,y,z}, 1})
    for x <- 0..(state.width - 1), y <- 14..14, z <- 0..(state.length - 1), do: :ets.insert(state.map_table, {{x,y,z}, 12})
    for x <- 0..(state.width - 1), y <- 15..15, z <- 0..(state.length - 1), do: :ets.insert(state.map_table, {{x,y,z}, 9})
  end
end
