#!/usr/bin/env node
/**
 * Build-time guard for the pnpm entry point inside the runtime tree.
 *
 * The shell and the Host both hand pnpm's path to the plugin manager from a
 * literal compiled into their bundle, and neither searches for it. A location
 * that does not exist breaks no build and no launch: it fails on the first
 * plugin operation, as `Cannot find module .../pnpm/bin/pnpm.mjs`, which names
 * the plugin rather than the layout.
 *
 * The path is read out of both bundles rather than restated here, because the
 * two anchor it differently and the Host's base is not written down: the shell
 * resolves it under `process.resourcesPath`, the Host under its `supportDir`,
 * which is pinned to the directory the shell itself names as the standalone Node
 * launcher. The file is then tied to the primary-runtime payload root, where the
 * payload's own consumer reads it after installation under the Harness home, and
 * executed through the packaged launcher the way the Host runs it.
 *
 * Usage: desktop-runtime-pnpm.mjs <app-root> <resources-root> <launcher>
 */
import { execFileSync } from "node:child_process"
import { existsSync, readFileSync, statSync } from "node:fs"
import { dirname, join } from "node:path"

const [, , appRoot, resourcesRoot, launcher] = process.argv
if (appRoot === undefined || resourcesRoot === undefined || launcher === undefined) {
  console.error("usage: desktop-runtime-pnpm.mjs <app-root> <resources-root> <launcher>")
  process.exit(2)
}

function fail(lines) {
  console.error(lines.map(line => `desktop pnpm: ${line}`).join("\n"))
  process.exit(1)
}

/**
 * The single `join(<base>, "a", "b", ...)` call in `source` whose last segment
 * is `last`, as the segments after the base. Exactly one match is required: two
 * literals would mean the tree has to satisfy two layouts at once.
 * @param {string} source - Shipped bundle to read.
 * @param {string} base - Regex for the join() base, e.g. `process\.resourcesPath`.
 * @param {string} last - Final path segment, e.g. `pnpm.mjs`.
 * @param {string} what - Human-readable name of the file being read.
 * @returns {string[]} Path segments after the base.
 */
function resolveLiteral(source, base, last, what) {
  const calls = [...source.matchAll(new RegExp(`join\\(\\s*${base}\\s*,([^)]*)\\)`, "gu"))]
  const matches = []
  for (const call of calls) {
    const segments = [...call[1].matchAll(/["']([^"']+)["']/gu)].map(match => match[1])
    if (segments.length > 0 && segments[segments.length - 1] === last) matches.push(segments)
  }
  if (matches.length !== 1) {
    fail([
      `expected exactly one ${last} path in ${what}, found ${matches.length}`,
      "upstream moved or renamed this literal; re-verify the layout this package assembles",
    ])
  }
  return matches[0]
}

const shell = readFileSync(join(appRoot, "lib", "main.js"), "utf8")
const host = readFileSync(join(appRoot, "dsh", "node_modules", "@deepseek-ai", "dsh-desktop-host", "lib", "cli.js"), "utf8")

const shellPnpm = resolveLiteral(shell, "process\\.resourcesPath", "pnpm.mjs", "the packaged shell (resources/app/lib/main.js)")
const entry = join(resourcesRoot, ...shellPnpm)
if (!existsSync(entry) || !statSync(entry).isFile()) {
  fail([
    `no pnpm entry point at ${entry}`,
    "the packaged shell and the Host both resolve pnpm there, so every plugin",
    "operation would fail with MODULE_NOT_FOUND; the runtime tree does not provide it",
  ])
}

// The Host resolves the same file under a base it does not write down, so that
// base is pinned to the directory the shell names as the Node launcher.
const shellNodeBin = resolveLiteral(shell, "process\\.resourcesPath", "bin", "the packaged shell (resources/app/lib/main.js)")
const hostBin = resolveLiteral(host, "supportDir", "bin", "the shipped Host (dsh-desktop-host/lib/cli.js)")
if (hostBin.length !== 1) {
  fail([
    `the Host's Node launcher directory is join(supportDir, ${JSON.stringify(hostBin.join("/"))}), expected exactly "bin"`,
    "the supportDir anchor below depends on it; re-verify the layout this package assembles",
  ])
}
const supportDir = join(resourcesRoot, ...shellNodeBin.slice(0, -1))
const hostPnpm = resolveLiteral(host, "supportDir", "pnpm.mjs", "the shipped Host (dsh-desktop-host/lib/cli.js)")
const hostEntry = join(supportDir, ...hostPnpm)
if (hostEntry !== entry) {
  fail([
    "the shell and the Host resolve pnpm to different files:",
    `    shell plugin manager: ${entry}`,
    `    Host CLI:             ${hostEntry}`,
    `(supportDir anchored at ${supportDir} via join(supportDir, "bin") == resources/${shellNodeBin.join("/")})`,
  ])
}

// The payload consumer behind load_workspace_dependencies reads pnpm at this
// path relative to the primary-runtime root, so it must sit inside that root.
const shellPayload = resolveLiteral(shell, "process\\.resourcesPath", "primary-runtime", "the packaged shell (resources/app/lib/main.js)")
const payloadRoot = join(resourcesRoot, ...shellPayload)
const relativeToPayload = shellPnpm.slice(shellPayload.length).join("/")
if (relativeToPayload !== "dependencies/pnpm/bin/pnpm.mjs") {
  fail([
    `the shell expects pnpm at ${entry}`,
    "but the payload consumer behind load_workspace_dependencies expects",
    `dependencies/pnpm/bin/pnpm.mjs under ${payloadRoot} (found ${relativeToPayload})`,
    "the packaged package manager and the tool would then use different pnpm binaries",
  ])
}

// Three records of the same pnpm, read by different consumers.
const descriptor = JSON.parse(readFileSync(join(appRoot, "dsh", "desktop-runtime.json"), "utf8"))
const manifest = JSON.parse(readFileSync(join(payloadRoot, "runtime.json"), "utf8"))
const pnpmPackage = join(dirname(dirname(entry)), "package.json")
const installed = JSON.parse(readFileSync(pnpmPackage, "utf8"))
const declared = [descriptor.release?.pnpmVersion, manifest.pnpm, installed.version]
if (declared.some(version => typeof version !== "string") || declared.some(version => version !== declared[0])) {
  fail([
    `the three records of the bundled pnpm disagree: ${declared.map(v => JSON.stringify(v)).join(" / ")}`,
    "(order: desktop-runtime.json release.pnpmVersion, primary-runtime runtime.json,",
    `the copied package at ${pnpmPackage})`,
  ])
}

// Resolving the path is not running it: bin/pnpm.mjs imports ../dist/pnpm.mjs,
// so a copy without the dist tree still resolves. The invocation is the Host's.
let reported
try {
  reported = execFileSync(launcher, ["--expose-internals", entry, "--version"], {
    encoding: "utf8",
    env: { ...process.env, ELECTRON_RUN_AS_NODE: "1" },
  }).trim()
} catch (error) {
  fail([
    `the pnpm entry point at ${entry} does not run the way the Host runs it`,
    `(${launcher} --expose-internals ${entry} --version, ELECTRON_RUN_AS_NODE=1)`,
    String(error.stderr ?? error.message).trim(),
  ])
}
if (reported !== declared[0]) {
  fail([`the pnpm entry point at ${entry} reports ${JSON.stringify(reported)}, expected ${declared[0]}`])
}

console.log(`  ok: pnpm ${declared[0]} resolves and runs at ${join("resources", ...shellPnpm)}, for the shell, the Host CLI and the payload consumer`)
