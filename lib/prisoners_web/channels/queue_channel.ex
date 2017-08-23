defmodule PrisonersWeb.QueueChannel do
    use PrisonersWeb, :channel
    require Logger

    def join("queue", _message, socket) do
        player = assign(socket, :player_id, UUID.uuid4())

        {:ok, player}
    end

    def handle_in("ping", payload, socket) do
        {:reply, {:ok, payload}, socket}
    end

    def handle_in("search:start", _, player) do
        player_id = player.assigns[:player_id]
        Prisoners.Queue.join(player)

        Logger.info "#{player_id} joined the queue"

        groups = Prisoners.Queue.pair()

        for group <- groups do
            game_id = UUID.uuid4()

            {_, _} = Prisoners.Game.start("game:" <> game_id, Map.keys(group))

            Logger.info("Game #{game_id} started with players #{Map.keys(group)}")

            for {_, player} <- group do
                Phoenix.Channel.push(player, "search:found", %{game_id: game_id, token: player.assigns[:player_id]})
            end
        end

        {:reply, :ok, player}
    end

    def handle_in("search:stop", _, player) do
        player_id = player.assigns[:player_id]
        Prisoners.Queue.leave(player)

        Logger.info "#{player_id} left the queue"

        {:reply, :ok, player}
    end

    def terminate(_, player) do
        player_id = player.assigns[:player_id]
        Prisoners.Queue.leave(player)

        Logger.info "#{player_id} disconnected from the queue"
    end
end
