defmodule Prisoners.Game do
    defstruct id: nil, pid: nil, player_ids: [], messages: [], start: nil, duration: nil

    defmodule PlayerInfo do
        defstruct id: nil, votes: %{}, time: nil, players: %{}, messages: []
    end

    defmodule Message do
        defstruct from: nil, to: nil, text: "", time: :os.system_time(:milli_seconds)
    end

    require Logger
    require IEx
    alias Prisoners.Game
    alias Prisoners.Player
    alias Phoenix.Channel

    @decisions ["cooperate", "betray"]
    @votes ["extend", "end"]
    @duration 60_000

    def run("" <> game_id, player_ids, duration \\ @duration) when is_list(player_ids) and is_integer(duration) do
        Logger.info fn -> "#{game_id}: Starting game with #{player_ids}" end

        game_name = String.to_atom(game_id)
        
        {:ok, ref} = Agent.start_link(fn ->
            for player_id <- player_ids do
                Player.create(player_id, List.delete(player_ids, player_id))
            end
            
            %Game{
                id: game_id,
                pid: self(),
                duration: duration,
                start: :os.system_time(:milli_seconds),
                player_ids: player_ids,
                messages: []
            }
        end, name: game_name)

        Logger.info fn -> "#{game_id}: Started game with #{player_ids}" end
        Logger.debug fn -> "#{game_id}: Started process #{inspect(ref)}" end

        loop(game_id, duration)

        Logger.info fn -> "#{game_id}: Ended game" end
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

        broadcast(game_id, "update:result", %{result: result(game_id)})

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

        Player.connect(player_id, socket)

        :ok
    end

    def leave("" <> game_id, "" <> player_id) do
        Logger.info fn -> "#{game_id}: #{player_id} left the game" end

        Player.disconnect(player_id)

        :ok
    end

    ##
    # Player input
    ##
    def decide("" <> game_id, "" <> player_id, decision, "" <> opponent_id) when decision in @decisions do
        Logger.info fn -> "#{game_id}: #{player_id} decided to #{decision} with #{opponent_id}" end

        player = Player.get(player_id)

        if player.decisions |> Map.has_key?(opponent_id) do
            Player.decide(player_id, opponent_id, decision)
        else
            :err
        end
    end
    def decide(_, _, _, _), do: :err

    def say("" <> game_id, "" <> from_player_id, "" <> message) when message != "" do
        Logger.info fn -> "#{game_id}: #{from_player_id} says '#{message}'" end

        message_data = parse_message(game_id, from_player_id, message)
        save_message(game_id, message_data)

        broadcast(game_id, "update:message", message_data)

        :ok
    end
    def say(_, _, _) do :err end

    def say("" <> game_id, "" <> from_player_id, "" <> message, "" <> to_player_id) when message != "" do
        if has_player?(game_id, from_player_id) and has_player?(game_id, to_player_id) do
            Logger.info fn -> "#{game_id}: #{from_player_id} says '#{message}' to #{to_player_id}" end

            message_data = parse_message(game_id, from_player_id, message, to_player_id)
            save_message(game_id, message_data)

            for player_id <- [from_player_id, to_player_id] do
                Player.send(player_id, "update:message", message_data)
            end

            :ok
        else
            :err
        end
    end
    def say(_, _, _, _) do :err end

    def vote("" <> game_id, "" <> player_id, "" <> vote_for, flag) when is_boolean(flag) and vote_for in @votes do
        Logger.info fn -> "#{game_id}: #{player_id} #{flag && "voted to #{vote_for}" || "canceled his #{vote_for} vote"}" end

        {vote_approved, pid} = game_id
        |> String.to_atom
        |> Agent.get(fn game ->
            Player.vote(player_id, vote_for, flag)

            vote_approved = game.player_ids |> Player.get |> Enum.all?(fn player -> player.votes[vote_for] end)

            {vote_approved, game.pid}
        end)
        
        if vote_approved do
            vote_reset(game_id, vote_for)
        end

        game = get(game_id)

        count = Enum.count(game.player_ids |> Player.get, fn player ->
            player.votes[vote_for]
        end)
        
        broadcast(game_id, "update:vote", %{"vote" => vote_for, "count" => count})

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

        player = Player.get(player_id)

        %PlayerInfo{
            id: player_id,
            time: get_time(game_id),
            votes: player.votes,
            players: Player.get(player_id).opponent_ids
                |> Enum.reduce(%{}, fn opponent_id, acc ->
                put_in(acc[opponent_id], %{
                    id: opponent_id,
                    decision: player.decisions[opponent_id]
                })
            end),
            messages: get_messages(game_id, player_id)
        }
    end

    def get("" <> game_id), do: get(game_id, &(&1))
    def get("" <> game_id, foo) do
        game_id
        |> String.to_atom
        |> Agent.get(foo)
    end

    def has_player?("" <> game_id, "" <> player_id), do: player_id in get(game_id).player_ids

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

        get(game_id, fn %{player_ids: player_ids} -> player_id in player_ids end)
    end

    ##
    # Helper methods
    ##

    defp calculate_points(a, b) when a in @decisions and b in @decisions do
        case {a, b} do
            {"cooperate", "cooperate"} -> 15
            {"cooperate", "betray"} -> -15
            {"betray", "cooperate"} -> 15
            {"betray", "betray"} -> 0
        end
    end

    defp filter_message(%Message{from: from, to: to}, "" <> player_id) do
        from == player_id || to == player_id || to == nil
    end

    defp parse_message("" <> game_id, "" <> player_id, "" <> message, opponent_id \\ nil) do
        Logger.info fn -> "#{game_id}: Parsing message from #{player_id} to #{opponent_id || "everyone"}" end

        %Message{
            from: player_id,
            to: opponent_id,
            text: message
        }
    end

    defp save_message("" <> game_id, message = %Message{}) do
        game_id
        |> String.to_atom
        |> Agent.update(fn game ->
            update_in game.messages, &List.insert_at(&1, -1, message)
        end)
    end

    defp result("" <> game_id) do
        Logger.info fn -> "#{game_id}: Calculating result" end

        game = get(game_id)

        decisions = game.player_ids
        |> Player.get
        |> Enum.reduce([], fn %{decisions: decisions}, acc ->
            decisions
            |> Map.values
            |> Enum.concat(acc)
        end)
        |> Enum.dedup

        result = case decisions do
            ["cooperate"] -> give_everyone(game_id, 60)
            ["betray"] -> give_everyone(game_id, -60)
            _ -> game.player_ids
            |> Enum.reduce(%{}, fn player_id, acc ->
                res = Player.get(player_id).decisions
                |> Enum.reduce(0, fn {opponent_id, player_decision}, points ->
                    opponent_decision = Player.get(opponent_id).decisions[player_id]

                    points + calculate_points(player_decision, opponent_decision)
                end)

                Map.put(acc, player_id, res)
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

        broadcast(game_id, "update:extend", get_time(game_id))

        loop(game_id, duration)
    end

    defp give_everyone("" <> game_id, points) when is_integer(points) do
        get(game_id).player_ids
        |> Map.new(&({&1, points}))
    end

    defp broadcast("" <> game_id, "" <> channel, message) do
        Logger.info fn -> "#{game_id}: Broadcasting #{channel} => #{inspect(message)}" end

        get(game_id).player_ids
        |> List.first
        |> Player.get
        |> Map.get(:socket)
        |> Channel.broadcast(channel, message)
    end

    defp vote_reset("" <> game_id, "" <> vote_for) do
        Logger.info fn -> "#{game_id}: Resetting vote #{vote_for}" end

        get(game_id).player_ids
        |> Enum.each(&(Player.vote(&1, vote_for, false)))
    end
end