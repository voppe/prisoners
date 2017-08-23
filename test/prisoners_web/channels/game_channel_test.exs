defmodule PrisonersWeb.GameChannelTest do
  use PrisonersWeb.ChannelCase

  alias PrisonersWeb.GameChannel

  setup do    
    game_id = UUID.uuid4()
    {_pid, _ref} = Prisoners.Game.start game_id, ["a", "b", "c"]
    {:ok, _, player_a} =
      socket("a", %{})
      |> subscribe_and_join(GameChannel, game_id, %{"token" => "a"})
    {:ok, _, player_b} =
      socket("b", %{})
      |> subscribe_and_join(GameChannel, game_id, %{"token" => "b"})
    {:ok, _, player_c} =
      socket("c", %{})
      |> subscribe_and_join(GameChannel, game_id, %{"token" => "c"})

    {:ok, sockets: [player_a, player_b, player_c], game_id: game_id}
  end

  test "reject join to non-registered opponents", %{game_id: game_id} do
    res = socket("d", %{})
      |> subscribe_and_join(GameChannel, game_id, %{"token" => "d"})

    assert elem(res, 0) == :error, "Opponent joined with invalid token"
  end

  test "send messages to other opponents", %{sockets: [player | _]} do
    ref = push player, "action:message", %{text: "waddup"}
    assert_reply ref, :ok, _
    assert_broadcast "update:message", %{text: "waddup", from: player_id}
    assert player_id == player.assigns[:player_id]
  end

  test "whisper other opponents", %{sockets: [player, opponent, _]} do
    player_id = player.assigns[:player_id]
    opponent_id = opponent.assigns[:player_id]
    ref = push player, "action:message", %{text: "waddup", to: opponent_id}
    assert_reply ref, :ok, _
    assert_push "update:message", %{text: "waddup", from: from, to: to}
    assert from == player_id
    assert to == opponent_id
  end

  test "reject empty messages", %{sockets: [player | _]} do
    ref = push player, "action:message", %{text: ""}
    assert_reply ref, :err, _
  end

  test "reject empty whispers", %{sockets: [player, opponent, _]} do
    ref = push player, "action:message", %{text: "", to: opponent.assigns[:player_id]}
    assert_reply ref, :err, _
  end

  test "reject whisper to nonexisting opponents", %{sockets: [player | _]} do
    ref = push player, "action:message", %{text: "waddup", to: "ayylmao"}
    assert_reply ref, :err, _
  end

  test "accept valid decision", %{sockets: [player, opponent, _]} do
    ref = push player, "action:decision", %{player: opponent.assigns[:player_id], decision: "cooperate"}
    assert_reply ref, :ok, _
  end

  test "reject nonexisting decision", %{sockets: [player, opponent, _]} do
    ref = push player, "action:decision", %{player: opponent.assigns[:player_id], decision: "false"}
    assert_reply ref, :err, _
  end

  test "reject decision on nonexisting opponent", %{sockets: [player | _]} do
    ref = push player, "action:decision", %{player: "ayy", decision: "cooperate"}
    assert_reply ref, :err, _
  end
  
  test "reject decision on self", %{sockets: [player | _]} do
    ref = push player, "action:decision", %{player: player.assigns[:player_id], decision: "cooperate"}
    assert_reply ref, :err, _
  end

  test "receive result on game end", %{sockets: sockets, game_id: game_id} do
    players = Enum.zip(sockets, [
      [["b", "cooperate"], ["c", "cooperate"]],
      [["a", "cooperate"], ["c", "cooperate"]],
      [["a", "cooperate"], ["b", "cooperate"]]
    ])
    for {socket, decisions} <- players do
      for [opponent, decision] <- decisions do
        push socket, "action:decision", %{player: opponent, decision: decision}
      end
    end
    Prisoners.Game.stop(game_id)
    assert_broadcast "update:result", %{result: result}
    assert result |> Enum.all?(fn {_, pts} -> 60 == pts end), "Incorrect point amount returned: #{inspect(result)}"
  end

  test "reject malformed requests", %{sockets: [player | _]} do
    ref = push player, "action:decision", %{decision: :cooperate}
    assert_reply ref, :err, _
  end

  test "on rejoin, receive game info", %{sockets: [player, opponent, _], game_id: game_id} do
    opponent_id = opponent.assigns[:player_id]

    push opponent, "action:message", %{text: "waddup"}
    ref = push player, "action:decision", %{player: opponent_id, decision: "betray"}
    assert_reply ref, :ok, _

    {:ok, reply, _} =
      socket("a", %{})
      |> subscribe_and_join(GameChannel, game_id, %{"token" => "a"})
    assert reply.players[opponent_id].decision == :betray 
    assert %Prisoners.Game.Message{text: "waddup", from: ^opponent_id, to: nil} = reply.messages |> List.first
  end
end
