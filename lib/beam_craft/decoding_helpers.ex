defmodule BeamCraft.DecodingHelpers do
  @moduledoc """
  Utility methods used by `BeamCraft.Protocol` to decode packets received 
  from the client. A reference describing the structure of each packet 
  is available at [wiki.vg](http://wiki.vg/Classic_Protocol).

  Each packet starts with an ID byte, then contains zero or more fields of the
  following types:
  * ASCII String: `binary-size(64)`; Extra trailing spaces are added for strings that are smaller than 64 bytes.
  * Cartesian Coordinate: `signed-big-integer-size(16)`; Decoded as a 5 point precision float (divide by 32).
  * Status flag: `unsigned-big-integer-size(8)`
  * Yaw: `unsigned-big-integer-size(8)`
  * Pitch: `unsigned-big-integer-size(8)`
  """

  @spec decode_packet(binary()) :: {:ok, tuple(), binary()}
  @doc """
  Decode a binary into a single packet, returning any undecoded data.

  Supports:
    * Login (ID: 0)
    * Block Update (ID: 5)
    * Player Position (ID: 8)
    * Chat Message (ID: 13)
  """

  # Login Packet
  def decode_packet(<<0, 7, username :: binary-size(64), password :: binary-size(64), _unused, rest :: binary>>) do
    packet = {:login, String.trim(username), String.trim(password)}
    {:ok, packet, rest}
  end

  # Block Update
  def decode_packet(<<5, x :: signed-big-integer-size(16), y :: signed-big-integer-size(16), z :: signed-big-integer-size(16), mode, block_type, rest :: binary>>) do
    packet = if mode == 1 do
      {:block_created, x, y, z, block_type}
    else
      {:block_destroyed, x, y, z, block_type}
    end
    
    {:ok, packet, rest}
  end

  # Player Position
  def decode_packet(<<8, player_id :: signed-big-integer-size(8), ex :: signed-big-integer-size(16), ey :: signed-big-integer-size(16), ez :: signed-big-integer-size(16), yaw, pitch, rest :: binary>>) do
    x = ex/32
    y = ey/32
    z = ez/32

    packet = {:player_position, player_id, x, y, z, yaw, pitch}
    {:ok, packet, rest}
  end

  # Chat message
  def decode_packet(<<13, 255, message :: binary-size(64), rest :: binary>>) do
    packet = {:message, String.trim(message)}
    {:ok, packet, rest}
  end

  def decode_packet(rest) do
    {:ok, {:undefined}, rest}
  end
end
