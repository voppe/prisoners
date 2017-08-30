defmodule PrisonersWeb.GameChannel do
  alias Prisoners.Game
  use PrisonersWeb, :channel
  require Logger

  def join(game_id, %{"token" => player_id}, socket) do
    Logger.info "#{player_id} attempting to join #{game_id}"
    if authorized?(game_id, player_id) do
        player = assign socket, :player_id, player_id

        send(self(), :after_join)

        {:ok, Game.get_info(game_id, player_id), player}
    else
        {:error, %{reason: "unauthorized"}}
    end
  end
  def join(_, _ , _), do: {:error, "Invalid join request"}

  def handle_info(:after_join, player) do
    player_id = player.assigns[:player_id]

    Game.join(player.topic, player_id, player)

    broadcast! player, "update:status", %{player: player_id, status: :status_joined}

    {:noreply, player}
  end

  def handle_info(_, player) do
    {:noreply, player}
  end

  def handle_in("action:message", %{"text" => message, "to" => opponent_id}, player) when message != "" and opponent_id != "" do
    game_id = player.topic
    player_id = player.assigns[:player_id]

    res = Game.say(game_id, player_id, message, opponent_id)

    {:reply, res, player}
  end

  def handle_in("action:message", %{"text" => message}, player) when message != "" do
    game_id = player.topic
    player_id = player.assigns[:player_id]

    res = Game.say(game_id, player_id, message)

    {:reply, res, player}
  end

  def handle_in("action:decision", %{"decision" => decision, "player" => opponent_id}, player) do
    game_id = player.topic
    player_id = player.assigns[:player_id]

    res = Game.decide(game_id, player_id, decision, opponent_id)

    {:reply, res, player}
  end

  def handle_in("action:vote", %{"vote" => vote_for, "flag" => flag}, player) do
    game_id = player.topic
    player_id = player.assigns[:player_id]

    res = Game.vote(game_id, player_id, vote_for, flag == true)

    {:reply, res, player}
  end

  def handle_in(_, _, socket) do
    {:reply, :err, socket}
  end

  def terminate(_, player) do
    game_id = player.topic
    player_id = player.assigns[:player_id]

    Logger.info "#{game_id}: #{player_id} left the game"

    broadcast! player, "update:status", %{"player" => player_id, "status" => :status_left}
  end

  defp authorized?(game_id, player_id) do
    Game.can_join?(game_id, player_id)
  end
end
