defmodule BeamCraftTest do
  use ExUnit.Case
  doctest BeamCraft

  test "greets the world" do
    assert BeamCraft.hello() == :world
  end
end
