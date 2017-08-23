defmodule Prisoners.Game do
    defstruct pid: nil, players: %{}, messages: [], start: nil, duration: nil
    
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
     
    @decisions ["cooperate", "betray"]
    @votes ["extend", "end"]
    @duration 60000
    
    def run(game_id, player_ids, duration \\ @duration) do
        Logger.info "#{game_id}: Started with #{player_ids}"

        pid = self()
        
        {:ok, ref} = Agent.start_link(fn -> 
            %Prisoners.Game{
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
        end, name: String.to_atom(game_id))

        Logger.debug "#{game_id}: Started process #{inspect(ref)}"

        loop(game_id, duration)

        Logger.info "#{game_id}: Ended"
    end

    defp loop(game_id, duration) do
        receive do
            :game_extend -> extend(game_id)
        after
            duration -> stop(game_id)
        end
    end

    def start(game_id, player_ids) do
        spawn_monitor(Prisoners.Game, :run, [game_id, player_ids])
    end

    def stop(game_id) do
        Logger.info "#{game_id}: Stopped"

        get_players(game_id)
        |> Map.values
        |> List.first
        |> Map.get(:socket)
        |> Phoenix.Channel.broadcast("update:result", %{result: result(game_id)})

        String.to_atom(game_id)
        |> Agent.stop

        :ok
    end

    ##
    # Player join/leave
    ##

    def join(game_id, player_id, socket) do
        Logger.info "#{game_id}: #{player_id} joined the game"

        String.to_atom(game_id)
        |> Agent.update(fn game ->
            put_in(game.players[player_id].socket, socket)
        end)

        :ok
    end

    def leave(game_id, player_id) do
        Logger.info "#{game_id}: #{player_id} left the game"

        String.to_atom(game_id)
        |> Agent.update(fn game ->
            put_in(game.players[player_id].socket, nil)
        end)

        :ok
    end

    ##
    # Player input
    ##

    def decide(game_id, player_id, decision, opponent_id) when decision in @decisions do
        Logger.info "#{game_id}: #{player_id} decided to #{decision} with #{opponent_id}"
        
        String.to_atom(game_id)
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
    def say(game_id, from_player_id, message) do
        Logger.info "#{game_id}: #{from_player_id} says '#{message}'"

        player = get_players(game_id)[from_player_id].socket

        message_data = parse_message(game_id, from_player_id, message)
        
        Phoenix.Channel.broadcast! player, "update:message", message_data

        :ok
    end

    def say(_, _, "", _) do :err end
    def say(_, _, _, nil) do :err end
    def say(_, from_player_id, _, opponent_id) when from_player_id == opponent_id do :err end
    def say(game_id, from_player_id, message, opponent_id) do
        players = get_players(game_id)

        if players |> Map.has_key?(opponent_id) do
            Logger.info "#{game_id}: #{from_player_id} says '#{message}' to #{opponent_id}"

            message_data = parse_message(game_id, from_player_id, message, opponent_id)

            for socket_id <- [opponent_id, from_player_id] do
                Phoenix.Channel.push players[socket_id].socket, "update:message", message_data
            end

            :ok
        else 
            :err
        end
    end
    
    def vote(game_id, from_player_id, vote_for, flag) when is_boolean(flag) and vote_for in @votes do
        {vote_approved, pid} = String.to_atom(game_id)
        |> Agent.get_and_update(fn game ->
            Logger.info "#{game_id}: #{from_player_id} #{flag && "voted to #{vote_for}" || "canceled his #{vote_for} vote"}"
    
            player = game.players[from_player_id]
            game = put_in game.players[from_player_id].votes[vote_for], flag

            vote_approved = game.players |> Enum.all?(fn {_, player} -> player.votes[vote_for] end)

            game = case vote_approved do
                true ->
                    players = for {player_id, player} <- game.players, into: %{}, do: {player_id, put_in(player.votes[vote_for], false)}
                    %{ game |
                        players: players
                    }
                false -> game
            end

            {{vote_approved, game.pid}, game}
        end)

        if vote_approved do
            Logger.info "#{game_id}: Vote for game #{vote_for} was approved"

            send(pid, String.to_atom("game_" <> vote_for))
        end
    end

    ##
    # Getter methods
    ## 

    def get_info(game_id, player_id) do
        Logger.debug "#{game_id}: Getting information for #{player_id}"

        player = get_player(game_id, player_id)
        
        %PlayerInfo{
          id: player_id,
          time: get_time(game_id),
          votes: player.votes,
          players: get_opponents(game_id, player_id) |> Enum.reduce(%{}, fn opponent_id, acc -> 
              put_in(acc[opponent_id], %{
                  id: opponent_id,
                  decision: player.decisions[opponent_id]
              })
          end),
          messages: get_messages(game_id, player_id)
        }
    end

    def get_players(game_id) do
        Logger.debug "#{game_id}: Getting players"

        String.to_atom(game_id)
        |> Agent.get(&(&1.players))
    end

    def get_player(game_id, player_id) do
        get_players(game_id)[player_id]
    end

    def get_opponents(players, player_id) when is_list(players) do players |> Enum.filter(&(&1 != player_id)) end
    def get_opponents(players, player_id) when is_map(players) do players |> Map.keys |> get_opponents(player_id) end
    def get_opponents(game_id, player_id) when is_bitstring(game_id) do get_players(game_id) |> get_opponents(player_id) end

    def get_messages(game_id, player_id) do
        Logger.debug "#{game_id}: Getting #{player_id} messages"

        String.to_atom(game_id)
        |> Agent.get(fn %{messages: messages} -> Enum.filter(messages, &filter_message(&1, player_id)) end)
    end

    def get_time(game_id) do
        {start, duration} = String.to_atom(game_id) |> Agent.get(&({&1.start, &1.duration}))
        
        %{
              current: :os.system_time(:milli_seconds) - start,
              duration: duration
        }
    end

    def can_join?(game_id, player_id) do
        Logger.info "#{game_id}: Checking if #{player_id} can join"

        String.to_atom(game_id)
        |> Agent.get(fn %{players: players} -> Map.has_key?(players, player_id) end)
    end

    ## 
    # Helper methods
    ##

    defp calculate_points(:cooperate, :cooperate), do: 15
    defp calculate_points(:cooperate, :betray), do: -15
    defp calculate_points(:betray, :cooperate), do: 15
    defp calculate_points(:betray, :betray), do: 0

    defp filter_message(%Message{from: from, to: to}, player_id) do
        from == player_id || to == player_id || to == nil
    end

    defp parse_message(game_id, player_id, message, opponent_id \\ nil) do
        Logger.info "#{game_id}: Parsing message from #{player_id} to #{opponent_id || "everyone"}"

        message_data = %Message{
            from: player_id, 
            to: opponent_id,
            text: message
        }

        String.to_atom(game_id)
        |> Agent.update(fn game ->
            update_in game.messages, &List.insert_at(&1, -1, message_data)
        end)

        message_data
    end

    defp result(game_id) do
        players = get_players(game_id)
        
        case players
        |> Map.values
        |> Enum.reduce([], fn %{decisions: decisions}, acc ->
            decisions
            |> Map.values
            |> Enum.concat(acc)
        end)
        |> Enum.dedup do
            [:cooperate] -> give_everyone(players, 60)
            [:betray] -> give_everyone(players, -60)
            _ -> players
            |> Map.keys
            |> Enum.reduce(%{}, fn player_id, acc ->
                result = players[player_id].decisions
                |> Enum.reduce(0, fn {opponent_id, player_decision}, points ->
                    opponent_decision = players[opponent_id].decisions[player_id]

                    points + calculate_points(player_decision, opponent_decision)
                end)

                Map.put(acc, player_id, result)
            end)
        end
    end

    ##
    # Actions
    ##

    defp extend(game_id, duration \\ @duration) do
        Logger.info "#{game_id}: Timer extended"

        String.to_atom(game_id)
        |> Agent.update(fn game ->
            put_in game.start, game.start + duration
        end)

        get_players(game_id)
        |> Map.values
        |> List.first
        |> Map.get(:socket)
        |> Phoenix.Channel.broadcast("update:extend", get_time(game_id))

        loop(game_id, duration)
    end

    defp give_everyone(players, points) do
        players
        |> Map.keys
        |> Map.new(&({&1, points})) 
    end
end