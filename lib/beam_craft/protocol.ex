defmodule BeamCraft.Protocol do
  alias BeamCraft.EncodingHelpers, as: Encoding
  alias BeamCraft.DecodingHelpers, as: Decoidng

  @behaviour :ranch_protocol

  @moduledoc """
  This module impliments a ranch protcol capable of communicating with
  Minecraft classic clients.

  It communicates with `BeamCraft.GameServer` to send and recive updates to
  the game state. 

  Messages decoded (using `BeamCraft.DecodingHelpers.decode_packet/1`) are translated to:
  * Login -> `BeamCraft.GameServer.login/2`
  * Block Update -> either `BeamCraft.GameServer.create_block/4` or `BeamCraft.GameServer.destroy_block/4`
  * Player Position -> `BeamCraft.GameServer.update_position/5`
  * Chat Message -> `BeamCraft.GameServer.send_message/1`

  When the process recives a messages in the form of `{:send_packet, payload}`, it
  invokes `BeamCraft.EncodingHelpers.encode_packet/1` and sends the resulting binary
  to the connected client.
  """

  def start_link(ref, socket, transport, _opts) do
    pid = spawn_link(__MODULE__, :init, [ref, socket, transport])
    {:ok, pid}
  end

  @doc """
  Initialize function for the process.

  This accepts the socket from ranch, sets `acive: :once`
  on the socket, then enters its main loop.
  """
  def init(ref, socket, transport) do
    :ok = :ranch.accept_ack(ref)

    transport.setopts(socket, [active: :once])
    loop(socket, transport, <<>>)
  end

  defp loop(socket, transport, old_data) do
    transport.setopts(socket, [active: :once])

    receive do
      {:tcp, ^socket, new_data} ->
        {:ok, message, next_data} = Decoidng.decode_packet(old_data <> new_data)
	      :ok = handle_packet(socket, transport, message)
	      loop(socket, transport, next_data)
      {:tcp_closed, ^socket} ->
        BeamCraft.GameServer.logout()
      {:send_packet, payload} ->
	      packet = Encoding.encode_packet(payload)
	      transport.send(socket, packet)
	      loop(socket, transport, old_data)
      any ->
        IO.puts("Got unhandled message #{inspect any, pretty: true}")
        loop(socket, transport, old_data)
    end
  end

  defp handle_packet(socket, transport, {:login, username, password}) do
    # Log the user in
    {:ok, server_name, motd, player} = BeamCraft.GameServer.login(username, password)
    login_packet = Encoding.encode_packet({:server_info, server_name, motd, player.player_type})
    transport.send(socket, login_packet)

    # Send the map
    {map_length, map_width, map_height, map_data} = BeamCraft.GameServer.get_map_details

    # Initialize level data
    transport.send(socket, Encoding.encode_packet({:map_initialize}))

    # Send the map chunks
    chunks = Encoding.chunk_map(map_data)
    for chunk <- chunks, do: transport.send(socket, chunk)

    # Finalize by sending the map dimensions
    transport.send(socket, Encoding.encode_packet({:map_finalize, map_length, map_width, map_height}))

    # Spawn the player
    transport.send(socket, Encoding.encode_packet({:spawn_player, 255, player.username, player.x, player.y, player.z, player.pitch, player.yaw}))

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
end
