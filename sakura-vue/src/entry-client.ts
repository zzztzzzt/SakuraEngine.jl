import { createSkPanelApp } from './app'

const mountNode = document.getElementById('vue-panel')

if (mountNode) {
  createSkPanelApp().mount(mountNode)
}
