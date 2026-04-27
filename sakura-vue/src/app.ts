import { createSSRApp } from 'vue'
import template from '../.sakura/vue-template'
import setupUserLogic from './generated-logic'

export function createSkPanelApp() {
  return createSSRApp({
    template: template,
    setup() {
      // Execute the logic extracted from the .sk file
      const userVariables = setupUserLogic()
      
      // If setupUserLogic returns something, spread it, otherwise it's just a blank app
      return typeof userVariables === 'object' ? { ...userVariables } : {}
    },
  })
}
