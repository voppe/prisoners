<template>
    <div v-if="!playing">
        <span v-if="!joined">Joining...</span>
        <div v-if="joined">
            <button v-on:click="searchStart" v-if="!searching">Begin</button>
            <button v-on:click="searchStop" v-if="searching">Cancel</button>
        </div>
    </div>
</template>

<script>
import Game from './Game'
import socket from '../socket'
import router from '../router'

let channel = socket.channel("queue", {});

export default {
    name: "lobby",
    created() {
        channel.join()
            .receive("ok", resp => {
                console.log("Joined successfully", resp)
                this.searchStart()
                this.joined = true
            })
            .receive("error", resp => {
                console.log("Unable to join", resp)
            })

        channel
            .on("search:found", this.onGameFound)
    },
    data() {
        return {
            joined: false,
            searching: false,
            playing: false
        }
    },
    methods: {
        onGameEnd(result) {
            console.log(result)
        },
        onGameFound(game) {
            let id = game.game_id
            
            this.searching = false
            this.playing = true
            
            sessionStorage.setItem(id, game.token)
            router.push({ name: 'game', params: { id } })
        },
        searchStart: function() {
            this.searching = true
            channel.push("search:start")
        },
        searchStop: function() {
            this.searching = false
            channel.push("search:stop")
        }
    },
    components: {
        Game
    }
}
</script>