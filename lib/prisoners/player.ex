defmodule Prisoners.Player do
    defstruct id: nil, opponent_ids: [], decisions: %{}, socket: nil, votes: %{}

    alias Phoenix.Channel
    alias Prisoners.Player
    require Logger

    def create("" <> player_id, opponent_ids) do
        Logger.info fn -> "#{player_id}: Created player" end

        {:ok, _} = Agent.start_link(fn ->
            %Player{
                id: player_id,
                decisions: Map.new(opponent_ids, &({&1, "cooperate"})),
                opponent_ids: opponent_ids
            }
        end, name: player_id
        |> String.to_atom)
    end

    def get([player_id | player_ids]), do: [get(player_id) | get(player_ids)]
    def get([]), do: []
    def get("" <> player_id) do
        player_id
        |> String.to_existing_atom
        |> Agent.get(&(&1))
    end
    
    def decide("" <> player_id, decide_for, decision) do
        player_id
        |> String.to_existing_atom
        |> Agent.update(&(put_in(&1.decisions[decide_for], decision)))
    end
        
    def vote("" <> player_id, vote_for, vote) do
        player_id
        |> String.to_existing_atom
        |> Agent.update(&(put_in(&1.votes[vote_for], vote)))
    end

    def connect("" <> player_id, socket) do
        player_id
        |> String.to_existing_atom
        |> Agent.update(&(put_in(&1.socket, socket)))
    end

    def disconnect("" <> player_id) do
        connect(player_id, nil)
    end

    def send("" <> player_id, channel, message) do
        Channel.push Player.get(player_id).socket, channel, message
    end
end
