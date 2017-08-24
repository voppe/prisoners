<template>
    <div id="game" v-if="joined">
        <div>
            {{(Math.max(0, this.time.duration - this.time.current)/1000).toFixed(1)}}

            <button v-on:click="vote('extend', !extend)">
                <span v-if="!extend">Vote extend <VoteCount :max="3" :count="votes['extend']"/></span>
                <span v-else>Cancel extend <VoteCount :max="3" :count="votes['extend']"/></span>
            </button>
        </div>
        <ul>
            <li v-for="message in messages">
                <span v-if="message.from === player.id">You</span>
                <span v-else>{{message.from}}</span>
                <span v-if="message.to !== null">whispered to 
                <span v-if="message.to !== player.id">{{message.to}}</span>
                <span v-else>you</span>
                </span>
                <span v-else>said</span>: {{message.text}}
            </li>
        </ul>

        <ul>
            <li v-for="player in players">
                {{player.id}}
                <div>
                    <button v-on:click="decide(player.id, 'betray')" :disabled="player.decision === 'betray'">Betray</button>
                    <button v-on:click="decide(player.id, 'cooperate')" :disabled="player.decision === 'cooperate'">Cooperate</button>
                </div>
            </li>
        </ul>

        <div>
            <input v-model="message.text" @keyup.enter="isValidMessage() && send()" />
            <button v-on:click="send" :disabled="!isValidMessage()">Send</button>
            <select v-model="message.to">
                <option value="">Everyone</option>
                <option v-for="player in players">{{player.id}}</option>
            </select>
        </div>
    </div>
    <div v-else>
        Joining...
    </div>
</template>

<script>
    import socket from '../socket'
    import router from '../router'

    import VoteCount from './VoteCount.vue'

    export default {
        components: {
            VoteCount
        },
        name: "game",
        mounted() {
            this.gameid = this.$route.params.id

            let token = sessionStorage.getItem(this.gameid)

            console.log("Joining game", this.gameid, "with token", token.substr(0, 9)+"*");

            this.channel = socket.channel(`game:${this.gameid}`, { token })

            this.channel
                .join()
                .receive("ok", resp => {
                    console.log("Connected to", resp.id)

                    this.joined = true
                    this.players = resp.players
                    this.time = resp.time
                    this.player.id = resp.id
                    this.votes = resp.votes
                    this.messages = resp.messages

                    if(!this._countdown) {
                        this.startCountdown()
                    }
                })
                .receive("error", resp => {
                    console.error("Could not join game:", resp.reason)
                    router.replace('/')
                })

            this.channel
                .on("update:message", message => {
                    console.log("Received", message)

                    this.messages.push(message)
                })

            this.channel
                .on("update:result", message => {
                    console.log("Result", message)
                    this.joined = false

                    this.onGameEnd(message)
                })

            this.channel
                .on("update:vote", message => {
                    console.log("Received vote", message)
                    this.votes[message.vote] = message.count;
                })

            this.channel
                .on("update:extend", time => {
                    console.log("Received extend", time)
                    this.extend = false
                    this.time = time
                })
        },
        data() {
            return {
                gameid: null,
                joined: false,
                message: {
                    text: "",
                    to: ""
                },
                channel: null,
                player: {
                    id: null
                },
                players: [],
                messages: [],
                extend: false,
                time: {
                    current: 0,
                    finish: 0
                },
                votes: {
                    extend: 0
                }
            }
        },
        methods: {
            decide: function (player, decision) {
                this.players[player].decision = decision

                this.channel.push("action:decision", {
                    decision,
                    player
                })
            },
            send: function () {
                if (!this.isValidMessage()) return;

                this.channel.push("action:message", this.message)
                this.message.text = ""
            },
            vote: function (vote, flag) {
                console.log("Voting for ", vote, ":", flag)

                this[vote] = !this[vote] === true
                this.channel.push("action:vote", {
                    vote,
                    flag
                })
            },
            isValidMessage: function () {
                return this.message.text.length > 0;
            },
            startCountdown: function () {
                var lastTime = new Date().getTime()
                this._countdown = window.setInterval(() => {
                    var currentTime = new Date().getTime()
                    this.time.current += currentTime - lastTime
                    lastTime = currentTime
                }, 100);
            }
        }
    }
</script>