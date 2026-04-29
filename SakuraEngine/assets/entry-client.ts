import { createSkPanelApp } from './app'

const mountNode = document.getElementById('sk-hydration-area')

if (mountNode) {
  createSkPanelApp().mount(mountNode)
}
