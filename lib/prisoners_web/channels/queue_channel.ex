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

      Prisoners.Queue.pair()
      
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
