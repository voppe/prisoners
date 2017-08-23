import VueRouter from 'vue-router'

import Lobby from './components/Lobby'
import Game from './components/Game'

export default new VueRouter({
    routes: [
        { path: '/', name: "lobby", component: Lobby },
        { path: '/game/:id', name: "game", component: Game }
    ]
})