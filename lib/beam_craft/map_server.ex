defmodule BeamCraft.MapServer do
  alias BeamCraft.RleHelpers, as: Rle
  use GenServer

  defmodule State do
    defstruct map_table: :map_table, length: 512, width: 512, height: 64
  end
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(_opts) do
    map_table = :ets.new(:map_table, [:named_table])
    state = %State{map_table: map_table}
    generate_map(state)
    {:ok, state}
  end

  def handle_call({:get_map}, _from, state) do
    map_cells = Enum.sort_by(:ets.match(state.map_table, {:'$1', :'$2'}), fn([{y,z}, _]) -> {y,z} end)
    map_data = Enum.reduce(map_cells, <<>>, fn([_, v], acc) -> acc <> :binary.list_to_bin(Rle.decode(v)) end)
    
    {:reply, {state.length, state.width, state.height, map_data}, state}
  end

  def handle_call({:get_default_spawn}, _from, state) do
    {:reply, {64, 64 + 1.6, 32}, state}
  end

  def handle_call({:set_block, x, y, z, block_type}, _from, state) do
    set_block(state, x, y, z, block_type)    
    {:reply, :ok, state}
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

  defp generate_map(state) do
    # Fill the map with air
    air_row = Rle.encode(for _ <- 0..(state.width - 1), do: 0)
    for y <- 0..(state.height - 1), z <- 0..(state.length - 1), do: :ets.insert(state.map_table, {{y,z}, air_row})

    # Generate a flat map
    bedrock_edge = round(state.height / 2) - 3
    
    stone_row = Rle.encode(for _ <- 0..(state.width - 1), do: 1)
    dirt_row = Rle.encode(for _ <- 0..(state.width - 1), do: 3)
    grass_row = Rle.encode(for _ <- 0..(state.width - 1), do: 2)
    
    for y <- 0..bedrock_edge, z <- 0..(state.length - 1), do: :ets.insert(state.map_table, {{y,z}, stone_row})
    for y <- bedrock_edge..bedrock_edge + 1, z <- 0..(state.length - 1), do: :ets.insert(state.map_table, {{y,z}, dirt_row})
    for y <- bedrock_edge + 1..bedrock_edge + 2, z <- 0..(state.length - 1), do: :ets.insert(state.map_table, {{y,z}, grass_row})
  end

  defp set_block(state, x, y, z, block_type) do
    [{{^y, ^z}, rle_col}] = :ets.lookup(state.map_table, {y,z})
    
    old_col = Rle.decode(rle_col)
    new_col = List.replace_at(old_col, x, block_type)

    :ets.insert(state.map_table, {{y,z}, Rle.encode(new_col)})
  end

  defp get_block(state, x, y, z) do
    [{{^y, ^z}, rle_col}] = :ets.lookup(state.map_table, {y,z})
    
    col = Rle.decode(rle_col)
    Enum.at(col, x)
  end
end
