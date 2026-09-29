#!/usr/bin/env node
/**
 * Build-time coverage guard for the two explicit module lists in package.nix.
 *
 * package.nix names the Desktop shell's production modules (`appModules`) and the
 * Host's direct dependencies (`hostDependencies`) by hand. A name that upstream
 * adds later is absent from both and produces a launch-time
 * `ERR_MODULE_NOT_FOUND`, which is the failure mode an unattended upstream bump
 * would hit. This script turns that into a build failure that names the package.
 *
 * It is a necessary, not a sufficient, check: Cordis's loader imports plugins
 * through a computed specifier, so a module only reachable that way cannot be
 * proven present here. It therefore never removes a name; it only reports one.
 */
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs"
import { isBuiltin } from "node:module"
import { dirname, join, relative } from "node:path"

/**
 * Every specifier form a bundle can leave external: `from` (static and
 * re-export), `require(...)`, dynamic `import(...)`, and the side-effect
 * `import "pkg"`. The last form needs its own alternative -- `import` followed
 * by a quote, not by a parenthesis -- and it is easy to miss: the shipped
 * main.js already uses it (`import "node:timers/promises"`). `import.meta`
 * does not match, because a dot follows the keyword rather than a quote.
 */
const SPECIFIER = /(?:from|require|import)\s*\(?\s*["\x27]([^"\x27]+)["\x27]/gu

/** Specifiers main.js probes inside a try/catch, so they may stay unresolved. */
const OPTIONAL = new Set(["node-addon-require-builtin"])

/** Electron is supplied by the runtime binary, never by node_modules. */
function providedByRuntime(specifier) {
  return specifier === "electron" || specifier.startsWith("electron/")
}

function packageName(specifier) {
  const parts = specifier.split("/")
  return specifier.startsWith("@") ? parts.slice(0, 2).join("/") : parts[0]
}

/** Every JavaScript file the packaged shell ships. */
function shippedSources(root) {
  const files = []
  const visit = (directory) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name)
      if (entry.isDirectory()) visit(path)
      else if (/\.(?:c|m)?js$/u.test(entry.name)) files.push(path)
    }
  }
  for (const sub of ["lib", "renderer"]) {
    const directory = join(root, sub)
    if (existsSync(directory)) visit(directory)
  }
  return files
}

function checkApplication(root) {
  const modules = join(root, "node_modules")
  const offenders = []
  let scanned = 0
  for (const file of shippedSources(root)) {
    scanned += 1
    const body = readFileSync(file, "utf8")
    const seen = new Set()
    for (const match of body.matchAll(SPECIFIER)) {
      const specifier = match[1]
      if (specifier.startsWith(".") || specifier.startsWith("/") || specifier.startsWith("\0")) continue
      if (providedByRuntime(specifier)) continue
      if (specifier.startsWith("node:") || isBuiltin(specifier)) continue
      if (OPTIONAL.has(specifier) || seen.has(specifier)) continue
      seen.add(specifier)
      const directory = join(modules, packageName(specifier))
      if (!existsSync(directory) || !statSync(directory).isDirectory()) {
        offenders.push(`${relative(root, file)}: ${specifier}`)
      }
    }
  }
  return { offenders, scanned }
}

function checkHostDependencies(runtimeRoot, manifestPath) {
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"))
  // The two dependency kinds are staged in different places, because they are
  // reached in different ways. A scoped package becomes a plugin loaded through
  // the runtime tree, so package.nix links it into that tree's scope. A bare
  // name is resolved by Node itself, relative to the Host entry point, and the
  // root package's own manifest is the exact witness for that lookup -- the
  // entry point follows its symlink into the shared store tree, where the
  // sibling node_modules is the one Node consults. Joining a bare name onto the
  // scope instead points at @deepseek-ai/koffi, which never exists, and fails
  // the build for a package that is in fact present.
  const scope = join(runtimeRoot, "node_modules", "@deepseek-ai")
  const besideManifest = join(dirname(manifestPath), "node_modules")
  const dependencies = Object.keys(manifest.dependencies ?? {})
  const offenders = []
  for (const name of dependencies) {
    const target = name.startsWith("@deepseek-ai/")
      ? join(scope, name.slice("@deepseek-ai/".length))
      : join(besideManifest, name)
    if (!existsSync(target)) offenders.push(name)
  }
  return { offenders, scanned: dependencies.length }
}

const [, , mode, ...rest] = process.argv
if (mode === "app" && rest.length === 1) {
  const { offenders, scanned } = checkApplication(rest[0])
  if (offenders.length > 0) {
    console.error(offenders.map(line => `    ${line}`).join("\n"))
    process.exit(1)
  }
  console.log(`  ok: every bare import in ${scanned} shipped shell files resolves`)
} else if (mode === "host" && rest.length === 2) {
  const { offenders, scanned } = checkHostDependencies(rest[0], rest[1])
  if (offenders.length > 0) {
    console.error(`    not linked: ${offenders.join(", ")}`)
    process.exit(1)
  }
  console.log(`  ok: all ${scanned} Host runtime dependencies are linked`)
} else {
  console.error("usage: desktop-coverage.mjs app <app-root> | host <runtime-root> <host-package.json>")
  process.exit(2)
}
