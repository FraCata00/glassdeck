import { createApp } from 'vue'
import App from './App.vue'
import vuetify from './plugins/vuetify'
import reveal from './composables/reveal'
import './styles/main.css'

createApp(App).use(vuetify).directive('reveal', reveal).mount('#app')
