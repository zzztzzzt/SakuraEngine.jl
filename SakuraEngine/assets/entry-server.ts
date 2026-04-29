import { renderToString } from '@vue/server-renderer'
import { createSkPanelApp } from './app'

export async function renderVuePanel() {
  const app = createSkPanelApp()
  return await renderToString(app)
}
