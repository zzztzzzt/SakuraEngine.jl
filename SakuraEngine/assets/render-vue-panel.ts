import { writeFileSync } from 'node:fs'
import { renderVuePanel } from '../src/sakura/entry-server'

const args = process.argv.slice(2)
const outFlagIndex = args.indexOf('--out')
const outPath = outFlagIndex !== -1 && outFlagIndex < args.length - 1 ? args[outFlagIndex + 1] : null

const html = await renderVuePanel()

if (outPath) {
  writeFileSync(outPath, html)
} else {
  process.stdout.write(html)
}
