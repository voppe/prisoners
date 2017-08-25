defmodule Prisoners.Game do
    defstruct id: nil, pid: nil, players: %{}, messages: [], start: nil, duration: nil

    defmodule Player do
        defstruct id: nil, decisions: %{}, socket: nil, votes: %{}
    end

    defmodule PlayerInfo do
        defstruct id: nil, votes: %{}, time: nil, players: %{}, messages: []
    end

    defmodule Message do
        defstruct from: nil, to: nil, text: "", time: :os.system_time(:milli_seconds)
    end

    require Logger
    alias Prisoners.Game

    @decisions ["cooperate", "betray"]
    @votes ["extend", "end"]
    @duration 60_000

    def run("" <> game_id, player_ids, duration \\ @duration) when is_list(player_ids) and is_integer(duration) do
        Logger.info fn -> "#{game_id}: Started with #{player_ids}" end

        pid = self()

        {:ok, ref} = Agent.start_link(fn ->
            %Game{
                id: game_id,
                pid: pid,
                duration: duration,
                start: :os.system_time(:milli_seconds),
                players: player_ids
                    |> Enum.reduce(%{}, fn player_id, acc ->
                        decisions = player_ids
                        |> get_opponents(player_id)
                        |> Map.new(&({&1, :cooperate}))

                        Map.put(acc, player_id, %Player{id: player_id, decisions: decisions})
                    end),
                messages: []
            }
        end, name: game_id
        |> String.to_atom)

        Logger.debug fn -> "#{game_id}: Started process #{inspect(ref)}" end

        loop(game_id, duration)

        Logger.info fn -> "#{game_id}: Ended" end
    end

    defp loop("" <> game_id, duration) when is_integer(duration) do
        receive do
            :game_extend -> extend(game_id)
        after
            duration -> stop(game_id)
        end
    end

    def start("" <> game_id, player_ids) when is_list(player_ids) do
        spawn_monitor(Prisoners.Game, :run, [game_id, player_ids])
    end

    def stop("" <> game_id) do
        Logger.info fn -> "#{game_id}: Stopped" end

        game_id
        |> get_game
        |> broadcast("update:result", %{result: result(game_id)})

        game_id
        |> String.to_atom
        |> Agent.stop

        :ok
    end

    ##
    # Player join/leave
    ##

    def join("" <> game_id, "" <> player_id, socket) do
        Logger.info fn -> "#{game_id}: #{player_id} joined the game" end

        game_id
        |> String.to_atom
        |> Agent.update(fn game ->
            put_in(game.players[player_id].socket, socket)
        end)

        :ok
    end

    def leave("" <> game_id, "" <> player_id) do
        Logger.info fn -> "#{game_id}: #{player_id} left the game" end

        game_id
        |> String.to_atom
        |> Agent.update(fn game ->
            put_in(game.players[player_id].socket, nil)
        end)

        :ok
    end

    ##
    # Player input
    ##

    def decide("" <> game_id, "" <> player_id, decision, "" <> opponent_id) when decision in @decisions do
        Logger.info fn -> "#{game_id}: #{player_id} decided to #{decision} with #{opponent_id}" end

        game_id
        |> String.to_atom
        |> Agent.get_and_update(fn game ->
            decisions = game.players[player_id].decisions

            if decisions |> Map.has_key?(opponent_id) do
                {:ok, put_in(game.players[player_id].decisions[opponent_id], String.to_atom(decision))}
            else
                {:err, game}
            end
        end)
    end
    def decide(_, _, _, _), do: :err

    def say(_, _, "") do :err end
    def say("" <> game_id, "" <> from_player_id, "" <> message) do
        Logger.info fn -> "#{game_id}: #{from_player_id} says '#{message}'" end

        game_id
        |> get_game
        |> broadcast("update:message", parse_message(game_id, from_player_id, message))

        :ok
    end

    def say("" <> game_id, "" <> from_player_id, "" <> message, "" <> to_player_id) when message != "" do
        if has_player?(game_id, from_player_id) and has_player?(game_id, to_player_id) do
            Logger.info fn -> "#{game_id}: #{from_player_id} says '#{message}' to #{to_player_id}" end

            players = get_game(game_id).players
            message_data = parse_message(game_id, from_player_id, message, to_player_id)

            for player_id <- [from_player_id, to_player_id] do
                Phoenix.Channel.push players[player_id].socket, "update:message", message_data
            end

            :ok
        else
            :err
        end
    end
    def say(_, _, _, _) do :err end

    def vote("" <> game_id, "" <> from_player_id, "" <> vote_for, flag) when is_boolean(flag) and vote_for in @votes do
        Logger.info fn -> "#{game_id}: #{from_player_id} #{flag && "voted to #{vote_for}" || "canceled his #{vote_for} vote"}" end

        {vote_approved, pid} = game_id
        |> String.to_atom
        |> Agent.get_and_update(fn game ->
            game = put_in game.players[from_player_id].votes[vote_for], flag

            vote_approved = game.players |> Enum.all?(fn {_, player} -> player.votes[vote_for] end)

            game = case vote_approved do
                true -> vote_reset(game, vote_for)
                false -> game
            end

            {{vote_approved, game.pid}, game}
        end)

        game = get_game(game_id)

        count = Enum.count(game.players, fn {_, player} ->
            player.votes[vote_for]
        end)
        broadcast(game, "update:vote", %{"vote" => vote_for, "count" => count})

        if vote_approved do
            Logger.info fn -> "#{game_id}: Vote for game #{vote_for} was approved" end

            send(pid, String.to_atom("game_" <> vote_for))
        end
    end

    ##
    # Getter methods
    ##

    def get_info("" <> game_id, "" <> player_id) do
        Logger.debug fn -> "#{game_id}: Getting information for #{player_id}" end

        player = get_player(game_id, player_id)

        %PlayerInfo{
            id: player_id,
            time: get_time(game_id),
            votes: player.votes,
            players: game_id
                |> get_opponents(player_id) |> Enum.reduce(%{}, fn opponent_id, acc ->
                put_in(acc[opponent_id], %{
                    id: opponent_id,
                    decision: player.decisions[opponent_id]
                })
            end),
            messages: get_messages(game_id, player_id)
        }
    end

    def get_game("" <> game_id) do
        game_id
        |> String.to_atom
        |> Agent.get(&(&1))
    end

    def has_player?("" <> game_id, "" <> player_id), do: get_player(game_id, player_id) != nil
    def get_player("" <> game_id, "" <> player_id), do: get_game(game_id).players[player_id]

    def get_opponents(players, "" <> player_id) when is_list(players) do players |> Enum.filter(&(&1 != player_id)) end
    def get_opponents(players, "" <> player_id) when is_map(players) do players |> Map.keys |> get_opponents(player_id) end
    def get_opponents("" <> game_id, "" <> player_id) do get_game(game_id).players |> get_opponents(player_id) end

    def get_messages("" <> game_id, "" <> player_id) do
        Logger.debug fn -> "#{game_id}: Getting #{player_id} messages" end

        game_id
        |> String.to_atom
        |> Agent.get(fn %{messages: messages} -> Enum.filter(messages, &filter_message(&1, player_id)) end)
    end

    def get_time("" <> game_id) do
        {start, duration} = game_id
        |> String.to_atom |> Agent.get(&({&1.start, &1.duration}))

        %{
            current: :os.system_time(:milli_seconds) - start,
            duration: duration
        }
    end

    def can_join?("" <> game_id, "" <> player_id) do
        Logger.info fn -> "#{game_id}: Checking if #{player_id} can join" end

        game_id
        |> String.to_atom
        |> Agent.get(fn %{players: players} -> Map.has_key?(players, player_id) end)
    end

    ##
    # Helper methods
    ##

    defp calculate_points(a, b) when a in @decisions and b in @decisions do
        case {a, b} do
            {:cooperate, :cooperate} -> 15
            {:cooperate, :betray} -> -15
            {:betray, :cooperate} -> 15
            {:betray, :betray} -> 0
        end
    end

    defp filter_message(%Message{from: from, to: to}, "" <> player_id) do
        from == player_id || to == player_id || to == nil
    end

    defp parse_message("" <> game_id, "" <> player_id, "" <> message, opponent_id \\ nil) do
        Logger.info fn -> "#{game_id}: Parsing message from #{player_id} to #{opponent_id || "everyone"}" end

        message_data = %Message{
            from: player_id,
            to: opponent_id,
            text: message
        }

        game_id
        |> String.to_atom
        |> Agent.update(fn game ->
            update_in game.messages, &List.insert_at(&1, -1, message_data)
        end)

        message_data
    end

    defp result("" <> game_id) do
        Logger.info fn -> "#{game_id}: Calculating result" end

        game = get_game(game_id)

        decisions = game.players
        |> Map.values
        |> Enum.reduce([], fn %{decisions: decisions}, acc ->
            decisions
            |> Map.values
            |> Enum.concat(acc)
        end)
        |> Enum.dedup

        result = case decisions do
            [:cooperate] -> give_everyone(game, 60)
            [:betray] -> give_everyone(game, -60)
            _ -> game.players
            |> Map.keys
            |> Enum.reduce(%{}, fn player_id, acc ->
                result = game.players[player_id].decisions
                |> Enum.reduce(0, fn {opponent_id, player_decision}, points ->
                    opponent_decision = game.players[opponent_id].decisions[player_id]

                    points + calculate_points(player_decision, opponent_decision)
                end)

                Map.put(acc, player_id, result)
            end)
        end

        result
    end

    ##
    # Actions
    ##

    defp extend("" <> game_id, duration \\ @duration) when is_integer(duration) do
        Logger.info fn -> "#{game_id}: Timer extended" end

        game_id
        |> String.to_atom
        |> Agent.update(fn game ->
            put_in game.start, game.start + duration
        end)

        game_id
        |> get_game
        |> broadcast("update:extend", get_time(game_id))

        loop(game_id, duration)
    end

    defp give_everyone(game = %Game{}, points) when is_integer(points) do
        game.players
        |> Map.keys
        |> Map.new(&({&1, points}))
    end

    defp broadcast(game = %Game{}, "" <> message, payload) do
        Logger.info fn -> "#{game.id}: Broadcasting #{message} => #{inspect(payload)}" end

        game.players
        |> Map.values
        |> List.first
        |> Map.get(:socket)
        |> Phoenix.Channel.broadcast(message, payload)
    end

    defp vote_reset(game = %Game{}, vote) do
        Logger.info fn -> "#{game.id}: Resetting vote #{vote}" end

        players = for {player_id, player} <- game.players, into: %{} do
            {player_id, put_in(player.votes[vote], false)}
        end

        %{game | players: players}
    end
end