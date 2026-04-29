import { createSSRApp } from 'vue'
import template from './vue-template'
import setupUserLogic from './generated-logic'

export function createSkPanelApp() {
  return createSSRApp({
    template: template,
    setup() {
      const userVariables = setupUserLogic()
      return typeof userVariables === 'object' ? { ...userVariables } : {}
    },
  })
}
