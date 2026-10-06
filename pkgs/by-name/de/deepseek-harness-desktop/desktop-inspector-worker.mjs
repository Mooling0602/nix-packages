#!/usr/bin/env node
/**
 * Build-time guard for the experimental Inspector's Worker in the desktop app.
 *
 * The Inspector is a Host plugin that does its work in its own Worker
 * (packages/experimental/inspector/lib/index.js, spawnWorker). Two facts about
 * that Worker are easy to lose and impossible to notice until someone opens
 * developer mode:
 *
 *   1. It is spawned with an explicit `execArgv`, so it does not inherit the
 *      `--expose-internals` this package's launcher passes to the Host. The
 *      Worker entry (lib/worker.js) imports
 *      @deepseek-ai/dsh-app-boot/worker/profile-resolution-bootstrap first, and
 *      that module's worker-bootstrap region calls internalModules() with no
 *      try/catch. Without the flag the call reaches the prebuilt
 *      `node-addon-require-builtin` binary, which pattern-matches an exact
 *      per-build runtime fingerprint and accepts only Electron 43.0.0, 44.0.0
 *      and 45.0.0-alpha.6 -- never a nixpkgs patch release (44.3.0, 44.5.1).
 *      Activation then fails with "node-addon-require-builtin unsupported:
 *      Unsupported/no-context (unsupported Electron runtime fingerprint ...)".
 *      deepseek-harness-git patches the spawn site to pass the flag; this guard
 *      reads that patch back out of the shipped tree instead of trusting it.
 *   2. The flag has to work *per Worker* in the bundled Electron. It does (Node
 *      applies Worker execArgv to the Worker's own environment, and the
 *      addon's plain-`require` path then resolves every internal module), but
 *      that is exactly the kind of assumption that a future Electron or Node
 *      bump can invalidate in silence.
 *
 * Run it the way the desktop Host runs: ELECTRON_RUN_AS_NODE=1 <wrapper>.
 * Usage:
 *   ELECTRON_RUN_AS_NODE=1 deepseek-harness desktop-inspector-worker.mjs \
 *     <inspector lib/index.js> <profile-resolution-bootstrap.js>
 */
import { readFileSync } from "node:fs"
import { Worker, setEnvironmentData } from "node:worker_threads"
import { pathToFileURL } from "node:url"

/** Set by app-boot before it spawns every Harness-owned Worker. */
const WORKER_RESOLUTION_KEY = "@deepseek-ai/dsh-app-boot/profile-resolution"
/** A Worker that never reports back is a failure, not a slow build. */
const WORKER_DEADLINE_MS = 30_000

const [, , inspectorLib, bootstrap] = process.argv
if (inspectorLib === undefined || bootstrap === undefined) {
  console.error("usage: desktop-inspector-worker.mjs <inspector lib/index.js> <profile-resolution-bootstrap.js>")
  process.exit(2)
}

/** Fail with one or more already-formatted lines. */
function fail(lines) {
  console.error(lines.map(line => `inspector worker: ${line}`).join("\n"))
  process.exit(1)
}

const source = readFileSync(inspectorLib, "utf8")

// 1. The spawn site in the shipped tree must carry the flag, and exactly one
//    execArgv literal may exist there: a second Worker in this file would be
//    spawned with whatever upstream chose, and the patch in
//    deepseek-harness-git would not have touched the value this guard reads.
const literals = [...source.matchAll(/execArgv:\s*(\[[^[\]]*\])/gu)].map(match => match[1])
if (literals.length !== 1) {
  fail([
    `${inspectorLib} has ${literals.length} execArgv literals, expected exactly 1`,
    "upstream reworked spawnWorker; re-check deepseek-harness-git's installPhase patch",
    "before trusting this guard's answer.",
  ])
}
let execArgv
try {
  execArgv = JSON.parse(literals[0])
} catch {
  fail([`the shipped execArgv literal ${literals[0]} is not JSON`])
}
if (!Array.isArray(execArgv) || !execArgv.includes("--expose-internals")) {
  fail([
    `the Inspector spawns its Worker with execArgv ${literals[0]}`,
    "which drops the parent's --expose-internals. The Worker would resolve Node's",
    "internal module loader through the prebuilt addon, and every Electron that is",
    "not 43.0.0/44.0.0/45.0.0-alpha.6 fails activation in developer mode.",
  ])
}

// 2. That value has to reach the internal loader inside a Worker of this exact
//    Electron build. The resolution table is a stub -- internalModules() runs
//    before the router reads it -- so the bootstrap is expected to throw past
//    that point; only the addon's own failure means the fix stopped working.
setEnvironmentData(WORKER_RESOLUTION_KEY, { resolution: { packages: {}, routes: {} } })

const worker = new Worker(pathToFileURL(bootstrap), { execArgv })
const outcome = await new Promise(resolve => {
  const timer = setTimeout(() => {
    void worker.terminate()
    resolve({ timeout: true })
  }, WORKER_DEADLINE_MS)
  worker.once("error", error => {
    clearTimeout(timer)
    resolve({ error })
  })
  worker.once("exit", code => {
    clearTimeout(timer)
    resolve({ code })
  })
})

if (outcome.timeout === true) {
  fail([`the Inspector Worker did not finish within ${WORKER_DEADLINE_MS} ms`])
}
const message = outcome.error === undefined ? "" : String(outcome.error.message)
if (message.includes("node-addon-require-builtin")) {
  fail([
    "the Inspector Worker fell back to the prebuilt addon:",
    `  ${message.split("\n")[0]}`,
    `runtime: node ${process.versions.node}, V8 ${process.versions.v8}, electron ${process.versions.electron}`,
    `worker execArgv: ${JSON.stringify(execArgv)}`,
    "Node did not apply --expose-internals to this Worker, so the desktop app's",
    "developer mode would fail with the same error.",
  ])
}

const note = message === "" ? "loaded cleanly" : `failed only on this guard's stub resolution (${message.split("\n")[0]})`
console.log(`  ok: the Inspector Worker passes ${JSON.stringify(execArgv)} through and the profile-resolution bootstrap ${note} on electron ${process.versions.electron}`)
