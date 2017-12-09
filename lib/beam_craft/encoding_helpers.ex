defmodule BeamCraft.EncodingHelpers do
  @moduledoc """
  Utility methods used by BeamCraft.Protocol to encode packets received 
  from the client. A reference describing the structure of each packet 
  is available at [wiki.vg](http://wiki.vg/Classic_Protocol).
  
  See `BeamCraft.DecoingHelpers` for the field definitions.
  """
  
  @chunk_size 1024

  @spec encode_packet(tuple()) :: binary()
  @doc """
  Encode a tuple into a binary packet. If the tuple is
  not defined, this function will throw an error.

  It supports:
   * Server Info (ID: 0): `{:server_info, server_name, motd, _player_type}`
   * Map Initialize (ID: 2): `{:map_initialize}`
   * Map Chunk (ID: 3): `{:spawn_player, player_id, player_name, x, y, z, yaw, pitch}`
   * Spawn Player (ID: 4): `{:map_finalize, length, width, height}`
   * Set Block (ID: 6): `{:set_block,  x, y, z, block_type}`
   * Position Player (ID: 8): `{:position_player, player_id, x, y, z, yaw, pitch}`
   * Despawn Player (ID: 12): `{:despawn_player, player_id}`
   * Message Player (ID: 13): `{:message_player, player_id, message}`
  """

  # Server Info
  def encode_packet({:server_info, server_name, motd, _player_type}) do
    # TODO: Impliment flagging players as operators
    <<0, 7, String.pad_trailing(server_name, 64) :: binary, String.pad_trailing(motd, 64) :: binary, 0>>
  end

  # Map Initialize
  def encode_packet({:map_initialize}) do
    <<2>>
  end
 
  # Map Chunk
  def encode_packet({:map_chunk, data, index}) do
    pad_size = (@chunk_size - byte_size(data)) * 8
    padded_data = <<data :: binary , 0 :: unsigned-big-integer-size(pad_size)>>
    <<3, @chunk_size :: unsigned-big-integer-size(16), padded_data :: binary, index>>
  end

  # Spawn Player
  def encode_packet({:spawn_player, player_id, player_name, x, y, z, yaw, pitch}) do
    # Encode palayer position with 5 degrees of precision
    ix = round(x * 32)
    iy = round(y * 32)
    iz = round(z * 32)
    
    <<7, player_id :: signed-big-integer-size(8), String.pad_trailing(player_name, 64) :: binary, ix :: signed-big-integer-size(16), iy :: signed-big-integer-size(16), iz :: signed-big-integer-size(16), yaw, pitch>>
  end

  # Map Finalize
  def encode_packet({:map_finalize, length, width, height}) do
    <<4, length :: unsigned-big-integer-size(16), width :: unsigned-big-integer-size(16), height :: unsigned-big-integer-size(16)>>
  end

  # Set Block
  def encode_packet({:set_block,  x, y, z, block_type}) do
    <<6, x :: unsigned-big-integer-size(16), y :: unsigned-big-integer-size(16), z :: unsigned-big-integer-size(16), block_type>>
  end

  # Postion Player
  def encode_packet({:position_player, player_id, x, y, z, yaw, pitch}) do
    # Encode palayer position with 5 degrees of precision
    ix = round(x * 32)
    iy = round(y * 32)
    iz = round(z * 32)
    
    <<8, player_id :: signed-big-integer-size(8), ix :: unsigned-big-integer-size(16), iy :: unsigned-big-integer-size(16), iz :: unsigned-big-integer-size(16), yaw, pitch>>
  end

  # Despawn Player
  def encode_packet({:despawn_player, player_id}) do
    <<12, player_id :: signed-big-integer-size(8)>>
  end
  
  # Message Player
  def encode_packet({:message_player, player_id, message}) do
    <<13, player_id :: signed-big-integer-size(8), String.pad_trailing(message, 64) :: binary>>
  end

  def encode_packet(arg) do
    raise "Can't build packet with `#{inspect arg}`"
  end

  @spec chunk_map(list(integer)) :: list(binary)
  @doc """
  Takes a raw map array and converts it into a list of map chunk packets to send to 
  the client.
  """
  def chunk_map(map) do
    map_bin = :binary.list_to_bin(map)
    data = :zlib.gzip(<<length(map) :: unsigned-big-integer-size(32), map_bin :: binary>>)

    chunks = chunk_map(data, [])

    for {chunk, index} <- Enum.with_index(chunks), do: encode_packet({:map_chunk, chunk, index})
  end

  defp chunk_map(data, results) when byte_size(data) > @chunk_size do
    head = :binary.part(data, 0, @chunk_size)
    tail = :binary.part(data, @chunk_size, byte_size(data) - @chunk_size)
    chunk_map(tail, results ++ [head])
  end

  defp chunk_map(data, results) do
    results ++ [data]
  end
end
