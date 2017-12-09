defmodule BeamCraft.Protocol do
  @behaviour :ranch_protocol

  @moduledoc """
  This module impliments a ranch protcol capable of communicating with
  Minecraft classic clients.
  """

  @chunk_size 1024

  def start_link(ref, socket, transport, _opts) do
    pid = spawn_link(__MODULE__, :init, [ref, socket, transport])
    {:ok, pid}
  end

  def init(ref, socket, transport) do
    :ok = :ranch.accept_ack(ref)

    transport.setopts(socket, [active: :once])
    loop(socket, transport, <<>>)
  end

  defp loop(socket, transport, old_data) do
    transport.setopts(socket, [active: :once])

    receive do
      {:tcp, ^socket, new_data} ->
        {:ok, message, next_data} = receive_packet(old_data <> new_data)
	      :ok = handle_packet(socket, transport, message)
	      loop(socket, transport, next_data)
      {:tcp_closed, ^socket} ->
        BeamCraft.GameServer.logout()
      {:send_packet, payload} ->
	      packet = build_packet(payload)
	      transport.send(socket, packet)
	      loop(socket, transport, old_data)
      any ->
        IO.puts("Got unhandled message #{inspect any, pretty: true}")
        loop(socket, transport, old_data)
    end
  end

  # Login Packet
  defp receive_packet(<<0, 7, username :: binary-size(64), password :: binary-size(64), _unused, rest :: binary>>) do
    packet = {:login, String.trim(username), String.trim(password)}
    {:ok, packet, rest}
  end

  # Block update packet
  defp receive_packet(<<5, x :: unsigned-big-integer-size(16), y :: unsigned-big-integer-size(16), z :: unsigned-big-integer-size(16), mode, block_type, rest :: binary>>) do
    packet = if mode == 1 do
      {:block_created, x, y, z, block_type}
    else
      {:block_destroyed, x, y, z, block_type}
    end

    {:ok, packet, rest}
  end

  # Player Position
  defp receive_packet(<<8, player_id :: signed-big-integer-size(8), ex :: signed-big-integer-size(16), ey :: signed-big-integer-size(16), ez :: signed-big-integer-size(16), yaw, pitch, rest :: binary>>) do
    x = ex/32
    y = ey/32
    z = ez/32

    packet = {:player_position, player_id, x, y, z, yaw, pitch}
    {:ok, packet, rest}
  end

  # Message
  defp receive_packet(<<13, 255, message :: binary-size(64), rest :: binary>>) do
    packet = {:message, String.trim(message)}
    {:ok, packet, rest}
  end

  defp receive_packet(data) do
    {:ok, :undefined, data}
  end

  # Server Info
  defp build_packet({:server_info, server_name, motd, _player_type}) do
    # TODO: Implement operator users
    <<0, 7, String.pad_trailing(server_name, 64) :: binary, String.pad_trailing(motd, 64) :: binary, 0>>
  end

  # Level Data Chunk
  defp build_packet({:map_chunk, data, index}) do
    pad_size = (@chunk_size - byte_size(data)) * 8
    padded_data = <<data :: binary , 0 :: unsigned-big-integer-size(pad_size)>>
    <<3, @chunk_size :: unsigned-big-integer-size(16), padded_data :: binary, index>>
  end

  # Spawn Player
  defp build_packet({:spawn_player, player_id, player_name, x, y, z, yaw, pitch}) do
    # Encode palayer position with 5 degrees of precision
    ix = round(x * 32)
    iy = round(y * 32)
    iz = round(z * 32)

    <<7,
    player_id :: signed-big-integer-size(8),
    String.pad_trailing(player_name, 64) :: binary,
    ix :: signed-big-integer-size(16),
    iy :: signed-big-integer-size(16),
    iz :: signed-big-integer-size(16),
    yaw, pitch>>
  end

  # Map Initialize
  defp build_packet({:map_initialize}) do
    <<2>>
  end

  # Map Finalize
  defp build_packet({:map_finalize, length, width, height}) do
    <<4, length :: unsigned-big-integer-size(16), width :: unsigned-big-integer-size(16), height :: unsigned-big-integer-size(16)>>
  end

  # Ping
  defp build_packet({:ping_player}) do
    <<1>>
  end

  # Set block
  defp build_packet({:set_block, x, y, z, type}) do
    <<6,
      x::signed-big-integer-size(16),
      y::signed-big-integer-size(16),
      z::signed-big-integer-size(16),
      type>>
  end

  # Teleport player
  defp build_packet({:position_player, player_id, x, y, z, yaw, pitch}) do
    ix = round(x * 32)
    iy = round(y * 32)
    iz = round(z * 32)

    <<8,
    player_id :: signed-big-integer-size(8),
    x::signed-big-integer-size(16),
    y::signed-big-integer-size(16),
    z::signed-big-integer-size(16),
    yaw::size(8),
    pitch::size(8)>>
  end

  # Update player pose
  defp build_packet({:update_player_pose, player_id, dx, dy, dz, yaw, pitch}) do
    <<9,
    player_id :: signed-big-integer-size(8),
    dx::signed-big-integer-size(16),
    dy::signed-big-integer-size(16),
    dz::signed-big-integer-size(16),
    yaw::size(8),
    pitch::size(8)>>
  end

  # Update player pose
  defp build_packet({:update_player_position, player_id, dx, dy, dz}) do
    <<0x0a,
    player_id :: signed-big-integer-size(8),
    dx::signed-big-integer-size(16),
    dy::signed-big-integer-size(16),
    dz::signed-big-integer-size(16)
    >>
  end

  # Update player orientation
  defp build_packet({:update_player_orientation, player_id, yaw, pitch}) do
    <<0x0b,
    player_id :: signed-big-integer-size(8),
    yaw::size(8),
    pitch::size(8)
    >>
  end

  # Despawn player
  defp build_packet({:despawn_player, player_id}) do
    <<0x0c,
      player_id::signed-size(8)
    >>
  end

  # Message
  defp build_packet({:message_player, player_id, msg}) do
    <<0x0d,
      player_id::signed-size(8),
      String.pad_trailing(msg, 64) :: binary
    >>
  end

  # Disconnect player
  defp build_packet({:disconnect_player, reason}) do
    <<0x0e,
      String.pad_trailing(reason, 64) :: binary
    >>
  end

  # Update user type
  defp build_packet({:update_user_type, type}) do
    <<0x0f,
      type::size(8)
    >>
  end

  defp build_packet(any) do
    raise "Can't build a packet for: #{inspect any}"
  end

  defp handle_packet(socket, transport, {:login, username, password}) do
    # Log the user in
    {:ok, server_name, motd, player} = BeamCraft.GameServer.login(username, password)
    login_packet = build_packet({:server_info, server_name, motd, player.player_type})
    transport.send(socket, login_packet)

    # Send the map
    {map_length, map_width, map_height, map_data} = BeamCraft.GameServer.get_map_details

    # Initialize level data
    transport.send(socket, build_packet({:map_initialize}))

    # Add the number of blocks, then gzip
    data = :zlib.gzip(<<(map_length * map_width * map_height) :: unsigned-big-integer-size(32), :binary.list_to_bin(map_data) :: binary>>)
    # Send as chunks of 1024
    for {chunk, index} <- Enum.with_index(chunk_map(data)), do: transport.send(socket, build_packet({:map_chunk, chunk, index}))

    # Finalize by sending the map dimensions
    transport.send(socket, build_packet({:map_finalize, map_length, map_width, map_height}))

    # TODO: this data should come from login
    # Spawn the player
    transport.send(socket, build_packet({:spawn_player, 255, player.username, player.x, player.y, player.z, player.pitch, player.yaw}))
    :ok
  end

  defp handle_packet(_, _, {:message, message}) do
    BeamCraft.GameServer.send_message(message)
  end

  defp handle_packet(_, _, {:player_position, _player_id, x, y, z, yaw, pitch}) do
    BeamCraft.GameServer.update_position(x, y, z, yaw, pitch)
  end

  defp handle_packet(_, _, {:block_created, x, y, z, block_type}) do
    BeamCraft.GameServer.create_block(x, y, z, block_type)
  end

  defp handle_packet(_, _, {:block_destroyed, x, y, z, block_type}) do
    BeamCraft.GameServer.destroy_block(x, y, z, block_type)
  end

  defp handle_packet(_, _, _) do
    :ok
  end

  defp chunk_map(data) do
    chunk_map(data, [])
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
