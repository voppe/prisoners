defmodule PrisonersWeb.QueueChannelTest do
  use PrisonersWeb.ChannelCase, async: false

  alias PrisonersWeb.QueueChannel

  setup do
    {:ok, _, socket} =
      socket("user_id", %{some: :assign})
      |> subscribe_and_join(QueueChannel, "queue")

    {:ok, socket: socket}
  end

  test "ping replies with status ok", %{socket: socket} do
    ref = push socket, "ping", %{"hello" => "there"}
    assert_reply ref, :ok, %{"hello" => "there"}
  end

  test "search start", %{socket: socket} do
    ref = push socket, "search:start", %{}
    assert_reply ref, :ok, %{}
  end

  test "search stop", %{socket: socket} do
    ref = push socket, "search:stop", %{}
    assert_reply ref, :ok, %{}
  end

  #test "game creation", _ do
  #  players = do_join(3)
    
  #  for player <- players do
  #    {:ok, _, socket} = player
  #    ref = push socket, "search:start", %{}
  #    assert_reply ref, :ok, %{}
  #  end
    
  #  games = Prisoners.Queue.pair()

  #  assert games |> length == 1, "Game started count does not match, got #{games |> length} instead of 1" 
  #  assert_push "search:found", %{game_id: _}
  #end
  
  #test "stress test queue", _ do
  #  players = do_join(1000)
    
  #  for player <- players do
  #    {:ok, _, socket} = player
  #    ref = push socket, "search:start", %{}
  #    assert_reply ref, :ok, %{}
  #  end
    
  #  games = Prisoners.Queue.pair()
  #  participants = games |> Enum.reduce([], &(&1 |> Map.keys |> Enum.concat(&2)))
    
  #  assert games |> Enum.all?(&(&1 |> Map.keys |> length == 3)), "More than 3 participants in game"
  #  assert length(participants) == length(participants |> Enum.sort |> Enum.dedup), "One participant is in multiple games"
  #  assert games |> length == div(1000, 3), "Game started count does not match, got #{games |> length} instead of #{div(1000, 3)}" 
  #  assert_push "search:found", %{game_id: _}
  #end 

  #defp do_join(amount) when amount > 0 do do_join([], amount) end
  #defp do_join(list, amount) when amount > 0 do 
  #  [socket("socket_#{amount}", %{}) |> subscribe_and_join(QueueChannel, "queue") | list] |> do_join(amount-1)
  #end
  #defp do_join(list, _) do list end 
end
