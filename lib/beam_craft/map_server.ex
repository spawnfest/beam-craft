defmodule BeamCraft.MapServer do
  alias BeamCraft.RleHelpers, as: Rle
  use GenServer

  @moduledoc """
  MapServer maintains the state of the map, and runs the logic needed for water to flow automaticly.

  This really wants to be started before other gameservers, since initialization can take a bit.
  """

  ###############################
  ## Public API
  ###############################

  @doc """
    Get the current map ETS table munged into a binary.

    Each byte corresponds to a single block.
    Layout is:

    [[xz slice[x row]]]
  """
  def get_map() do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:get_map})
  end

  @doc """
    Get the default spawn location for this map.

    Return is of the form `{x, y, z}`.
  """
  def get_default_spawn() do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:get_default_spawn})
  end


  @doc """
    Set a block at a position to a given type.

    Return is `:ok`.
  """
  def set_block(x, y, z, block_type) do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:set_block, x, y, z, block_type})
  end

  @doc """
    Runs the block transforms, if any, that're available.

    This handles things like propogating water, setting fire, and so forth.

    Return is of form `{:ok, []}` or `{:ok, [{:set_block, x, y, z, block_type},...]}`
  """
  def eval_block_transforms() do
    server_pid = :erlang.whereis(__MODULE__)
    GenServer.call(server_pid, {:eval_block_transforms})
  end

  ###############################
  ## Defines
  ###############################

  # Number of blocks to evaluate each time we are requested to do so
  @blocks_per_tick 20

  # Blocks which trigger update logic
  @air 0
  @flowing_water 8
  @still_water 9

  # Other blocks
  @sand 12
  @stone 1
  @bedrock 7
  @dirt 3
  @grass 2

  # map generation consants
  @bedrock_level 0
  #@sea_level 20
  #@sea_floor 10

  @map_length 512
  @map_width 512
  @map_height 64

  defmodule State do
    @moduledoc false
    defstruct map_table: :map_table, length: 512, width: 512, height: 64
  end

  ###############################
  ## Genserver
  ###############################

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
    map_cells = Enum.sort_by(:ets.match(state.map_table, {{:'$1', :'$2'}, :'$3'}), fn([y, z, _]) -> {y,z} end)
    map_data = Enum.reduce(map_cells, <<>>, fn([_, _, v], acc) -> acc <> :binary.list_to_bin(Rle.decode(v)) end)

    {:reply, {state.length, state.width, state.height, map_data}, state}
  end

  def handle_call({:get_default_spawn}, _from, state) do
    {:reply, {state.width/2, state.height-1.6, state.length/2}, state}
  end

  def handle_call({:set_block, x, y, z, block_type}, _from, state) do
    set_block(state, x, y, z, block_type)

    if block_type == @air do
      adjacent_water = adjacent_blocks(state, x, y, z, :look_up) |> Enum.filter(fn {_, _, _, type} -> type == @flowing_water || type == @still_water end)
      if length(adjacent_water) > 0, do: :ets.insert(state.map_table, {{x,y,z,block_type}, @flowing_water})
    end

    {:reply, :ok, state}
  end

  def handle_call({:eval_block_transforms}, _from, state) do
    updates = :ets.match(state.map_table, {{:'$1', :'$2', :'$3', :'$4'}, :'$5'}, @blocks_per_tick)

    case updates do
      {working_set, _} ->
	changes = eval_blocks(state, working_set)
	{:reply, {:ok, changes}, state}
      _ ->
	{:reply, {:ok, []}, state}
    end
  end

  ###############################
  ## Private helpers
  ###############################

  #
  # Generation helpers
  #
  defp on_border?(x,y,z) do
    y + 2 < (@map_height/2) && (
     z == 0 || z == @map_length-1
     || x == 0 || x == @map_width-1
     || y <= @bedrock_level
    )
  end

  defp in_water?(y,terrain_height) do
    y > terrain_height &&
    y - 2 < (@map_height/2)
  end

  defp underground?(y, terrain_height) do
    y < terrain_height
  end

  defp sample_terrain_height(x,z) do
    u = x / @map_width
    v = z / @map_length

    w = 0.3*(:math.sin(35*u) * :math.cos(17*v))
    (w+0.5) * @map_height
  end

  defp sample_map(x,y,z) do
    terrain_height = sample_terrain_height(x,z)
    cond do
      on_border?(x,y,z) -> @bedrock
      in_water?(y,terrain_height) ->
        if y < terrain_height do
          @sand
        else
          @still_water
        end
      underground?(y,terrain_height) ->
        cond do
          y + 3 < terrain_height -> @stone
          y + 1 < terrain_height -> @dirt
          y - 3 < (@map_height/2) -> @sand
          y  < terrain_height -> @grass
        end
      true -> @air
    end
  end

  defp generate_map(state) do
    (for y <- 0..(state.height - 1), z <- 0..(state.length - 1), do: [y,z])
    |> Enum.map( fn([y,z])->
      row = for x <- 0..(state.width-1) do
        sample_map(x,y,z)
      end
      :ets.insert(state.map_table, {{y,z}, Rle.encode(row)})
    end)
  end

  #
  # Block helpers
  #

  defp set_block(state, x, y, z, block_type) do
    [{{^y, ^z}, rle_col}] = :ets.lookup(state.map_table, {y,z})

    old_col = Rle.decode(rle_col)
    new_col = List.replace_at(old_col, x, block_type)

    :ets.insert(state.map_table, {{y,z}, Rle.encode(new_col)})

    {:set_block, x, y, z, block_type}
  end

  defp get_block(state, x, y, z) do
    [{{^y, ^z}, rle_col}] = :ets.lookup(state.map_table, {y,z})

    col = Rle.decode(rle_col)
    Enum.at(col, x)
  end

  defp adjacent_blocks(state, x, y, z, look) do
    base_points = [
      {x - 1, y ,z}, {x + 1, y, z},
      {x, y, z - 1}, {x, y, z + 1}
    ]

    top_point = case look do
		  :look_up ->
		    [{x, y + 1, z}]
		  :look_down ->
		    [{x, y - 1, z}]
		end

    points = base_points ++ top_point |> Enum.filter(fn {gx, gy, gz} -> gx >= 0 && gy >= 0 && gz >= 0 && gx < state.width && gy < state.height && gz < state.length end)
    Enum.map(points, fn {gx, gy, gz} -> {gx, gy, gz, get_block(state, gx, gy, gz)} end)
  end

  defp eval_blocks(state, updates) do
    valid_updates = Enum.filter(updates, fn [x, y, z, from, _] ->
      :ets.delete(state.map_table, {x, y, z, from})
      current = get_block(state, x, y, z)

      current == from
    end)

    updates = Enum.map(valid_updates, fn [x, y, z, from, to] ->
      cond do
	     to == @flowing_water ->
	       :ets.insert(state.map_table, {{x, y, z, to}, @still_water})
	       [set_block(state, x, y, z, to)]
	     from == @flowing_water && to == @still_water ->
	       adjacent_air = adjacent_blocks(state, x, y, z, :look_down)
                        |> Enum.filter(fn {_, _, _, type} -> type == @air end)
	       for {gx, gy, gz, _} <- adjacent_air do
          :ets.insert(state.map_table, {{gx, gy, gz, @flowing_water}, @flowing_water})
         end
	       [set_block(state, x, y, z, to)] ++ (for {x, y, z, _} <- adjacent_air, do: set_block(state, x, y, z, @flowing_water))
	     true ->
	       [set_block(state, x, y, z, to)]
      end
    end)

    List.flatten(updates)
  end
end
