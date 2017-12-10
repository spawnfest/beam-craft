defmodule BeamCraft.RleHelpers do
  @moduledoc """
  Utilities to perform run length encoding on a list of terms. 
  """
  
  @spec encode([any()]) :: [{integer(), any()}]
  @doc """
  Encode a list of terms.
  
  ## Examples
      iex> BeamCraft.RleHelpers.encode([1,2,3,4,5])
      [{1, 5}, {1, 4}, {1, 3}, {1, 2}, {1, 1}]
  """
  def encode(list) do
    fold_fn = fn
      term, [{count, term}|rest] -> [{count + 1, term}] ++ rest
      term, current -> [{1, term}] ++ current
    end
      
    Enum.reduce(list, [], fold_fn)    
  end

  @spec decode([{integer(), any()}]) :: [any()]
  @doc """
  Decode a list of terms.

  ## Examples
      iex> BeamCraft.RleHelpers.decode([{1, 5}, {1, 4}, {1, 3}, {1, 2}, {1, 1}])
      [1, 2, 3, 4, 5]
  """
  def decode(list) do
    Enum.reduce(list, [], fn {count, term}, acc -> (for _ <- 1..count, do: term) ++ acc end)
  end
end
