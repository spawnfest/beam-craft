defmodule BeamCraft.Protocol do
  @behaviour :ranch_protocol

  @moduledoc """ 
  This module impliments a ranch protcol capable of communicating with 
  Minecraft classic clients.
  """

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
	IO.puts "TCP: #{inspect new_data}"
	{:ok, message, next_data} = receive_packet(old_data <> new_data)
	IO.puts "MSG: #{inspect message}"
	:ok = handle_packet(socket, transport, message)
	loop(socket, transport, next_data)
      {:tcp_close, ^socket} ->
	IO.puts "[STUB]: Disconnect user"
      any ->
	IO.puts "Got: #{inspect any}"
	loop(socket, transport, old_data)
    end
  end

  # Login Packet
  # Packet ID, Protocol Version, Username, Password, Unused Byte
  defp receive_packet(<< 0, 7, username :: binary-size(64), password :: binary-size(64), _unused, rest :: binary>>) do
    IO.puts "Got a login packet for #{username}"
    packet = {:login, String.trim(username), String.trim(password)}
    {:ok, packet, rest}
  end
  
  defp receive_packet(data) do
    {:ok, :undefined, data}
  end

  # Server Info
  # Packet ID, Protocol Version, Name, Motd, Player Type
  defp build_packet({:server_info, server_name, motd, player_type}) do
    <<0, 7, String.pad_trailing(server_name, 64) :: binary, String.pad_trailing(motd, 64) :: binary, 0>>
  end

  defp build_packet(any) do
    raise "Can't build a packet for: #{inspect any}"
  end

  defp handle_packet(socket, transport, {:login, _, _}) do
    # TODO, replace this with calls to the game server
    stub_login = build_packet({:server_info, "yes", "yes", 1})
    transport.send(socket, stub_login)
    IO.puts "Sending login"
    :ok
  end

  defp handle_packet(_, _, _) do
    :ok
  end

end
