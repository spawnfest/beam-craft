defmodule DecodingHelpersTest do
  use ExUnit.Case

  test "decoding a login packet" do
    packet = <<0, 7, String.pad_trailing("test", 64) :: binary-size(64), String.pad_trailing("test", 64) :: binary-size(64), 0>>
    assert {:ok, {:login, "test", "test"}, <<>>} == BeamCraft.DecodingHelpers.decode_packet(packet)
  end

  test "decoding a block update packet which places a block" do
    packet = <<5, 512 :: signed-big-integer-size(16), 512 :: signed-big-integer-size(16), 512 :: signed-big-integer-size(16), 1, 16>>
    assert {:ok, {:block_created, 512, 512, 512, 16}, <<>>} == BeamCraft.DecodingHelpers.decode_packet(packet)
  end

  test "decoding a block update packet which removes a block" do
    packet = <<5, 512 :: signed-big-integer-size(16), 512 :: signed-big-integer-size(16), 512 :: signed-big-integer-size(16), 0, 16>>
    assert {:ok, {:block_destroyed, 512, 512, 512, 16}, <<>>} == BeamCraft.DecodingHelpers.decode_packet(packet)
  end
  
  test "decoding a player position packet" do
    packet = <<8, 255 :: signed-big-integer-size(8), 512 :: signed-big-integer-size(16), 512 :: signed-big-integer-size(16), 512 :: signed-big-integer-size(16), 0, 0>>
    assert {:ok, {:player_position, -1, 16, 16, 16, 0, 0}, <<>>} == BeamCraft.DecodingHelpers.decode_packet(packet)
  end

  test "decoding a chat message packet" do
    packet = <<13, 255, String.pad_trailing("test", 64) :: binary-size(64)>>
    assert {:ok, {:message, "test"}, <<>>} == BeamCraft.DecodingHelpers.decode_packet(packet)
  end

  test "decoding an unknown packet" do
    packet = <<7>>
    assert {:ok, {:undefined}, <<7>>} == BeamCraft.DecodingHelpers.decode_packet(packet)
  end
end
