// node --test wrapper for the Swift scenarios of ADR-2611240900, so a test runner hexa reads (node --test, TAP)
// reports each scenario. The Swift binary is compiled once per source state and cached.
// Run: node --test EarshotApp/Tests/call-audio.test.mjs
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync, spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { existsSync, readFileSync, mkdirSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const tests = dirname(fileURLToPath(import.meta.url))
const app = dirname(tests)
const testFile = join(tests, 'CallAudioTests.swift')
const header = readFileSync(testFile, 'utf8').match(/^\/\/ sources: *(.+)$/m)
const sources = header ? header[1].trim().split(/\s+/) : []

function binary() {
  const files = [...sources.map((s) => join(app, s)), testFile]
  const key = createHash('sha1')
  for (const f of files) key.update(existsSync(f) ? readFileSync(f) : 'missing:' + f)
  const dir = join(tmpdir(), 'earshot-call-audio-tests')
  mkdirSync(dir, { recursive: true })
  const out = join(dir, key.digest('hex'))
  if (!existsSync(out)) {
    execFileSync('swiftc', ['-O', '-swift-version', '5', '-target', 'arm64-apple-macosx26.4', '-parse-as-library',
      ...files.slice(0, -1), testFile, '-o', out], { cwd: app, stdio: 'pipe' })
  }
  return out
}

const bin = binary()
for (let n = 1; n <= 26; n++) {
  const name = 'S' + String(n).padStart(2, '0')
  test(name, () => {
    const r = spawnSync(bin, [name], { cwd: app, encoding: 'utf8' })
    assert.equal(r.status, 0, r.stdout + r.stderr)
  })
}
