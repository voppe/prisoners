defmodule Prisoners.Queue do
    require Logger

    def start_link do
        Agent.start_link(fn -> %{} end, name: __MODULE__)
    end

    def pair do
        groups = __MODULE__
        |> Agent.get_and_update(fn queue ->
            groups = queue
            |> Map.keys
            |> Enum.shuffle
            |> Enum.chunk(3)

            result = Enum.reduce(groups, [], fn group, acc ->
                [group
                |> Enum.reduce(%{}, fn player_id, acc ->
                    Map.put(acc, player_id, queue[player_id])
                end) | acc]
            end)

            state = Enum.reduce(groups, queue, fn player_ids, acc ->
                Map.drop(acc, player_ids)
            end)

            {result, state}
        end)

        groups
    end

    def join(player) do
        __MODULE__
        |> Agent.update(fn players ->
            Map.put(players, player.assigns[:player_id], player)
        end)
    end

    def leave(player) do
        __MODULE__
        |> Agent.update(fn players ->
            Map.delete(players, player.assigns[:player_id])
        end)
    end
end