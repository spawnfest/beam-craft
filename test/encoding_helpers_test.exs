defmodule EncodingHelpersTest do
  use ExUnit.Case

  test "encoding a server info packet" do
    expected = <<0, 7, String.pad_trailing("test", 64) :: binary, String.pad_trailing("test", 64) :: binary, 0>>
    given = {:server_info, "test", "test", 0}

    assert expected == BeamCraft.EncodingHelpers.encode_packet(given)
  end


  test "encoding a map initalize packet" do
    expected = <<2>>
    given = {:map_initialize}

    assert expected == BeamCraft.EncodingHelpers.encode_packet(given)
  end

  test "encoding a level data chunk packet" do
    expected = <<3, 1024 :: unsigned-big-integer-size(16), 0 :: integer-size(8192), 0>>
    given = {:map_chunk, <<>>, 0}

    assert expected == BeamCraft.EncodingHelpers.encode_packet(given)
  end

  test "encoding a spawn player packet" do
    expected = <<7, 255:: signed-big-integer-size(8), String.pad_trailing("test", 64) :: binary, 512 :: signed-big-integer-size(16), 512 :: signed-big-integer-size(16), 512 :: signed-big-integer-size(16), 0, 0>>
    given = {:spawn_player, 255, "test", 16, 16, 16, 0, 0}

    assert expected == BeamCraft.EncodingHelpers.encode_packet(given)
  end

  test "encoding a map finalize packet" do
    expected = <<4, 0, 0, 0, 0, 0, 0>>
    given = {:map_finalize, 0, 0, 0}

    assert expected == BeamCraft.EncodingHelpers.encode_packet(given)
  end

  test "encoding a set block packet" do
    expected = <<6, 0, 0, 0, 0, 0, 0, 0>>
    given = {:set_block,  0, 0, 0, 0}

    assert expected == BeamCraft.EncodingHelpers.encode_packet(given)
  end

  test "encoding a position player packet" do
    expected = <<8, 255, 0, 0, 0, 0, 0, 0, 0, 0>>
    given = {:position_player, -1, 0, 0, 0, 0, 0}

    assert expected == BeamCraft.EncodingHelpers.encode_packet(given)
  end

  test "encoding a message player packet" do
    expected =  <<13, 255, String.pad_trailing("test", 64) :: binary>>
    given = {:message_player, -1, "test"}

    assert expected == BeamCraft.EncodingHelpers.encode_packet(given)
  end
end
