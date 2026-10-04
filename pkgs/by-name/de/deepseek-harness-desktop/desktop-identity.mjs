#!/usr/bin/env node
/**
 * Build-time guard for the Linux desktop identity this package publishes.
 *
 * The identity has four spellings that all have to agree, or the window stops
 * matching its icon in a task bar:
 *
 *   app_id (Wayland)   } both derived by Electron from the application
 *   WM_CLASS (X11)     } manifest, not chosen by this package
 *   <id>.desktop         the file name the shell looks the window up by
 *   StartupWMClass       the X11 half of the same lookup
 *
 * Electron does not let the packager pick the app id unless the application
 * manifest carries `desktopName`. apps/desktop/package.json carries none and
 * declares only `"name": "@deepseek-ai/dsh-desktop"`, so the id is whatever
 * Electron's own fallback makes of that name -- a lowercased, hyphenated slug
 * (lib/browser/desktop-name.ts), which is "deepseek-ai-dsh-desktop" today.
 *
 * That is the trap this script exists for. The id is *derived*, so an upstream
 * rename of the private package would move it and silently stop matching the
 * installed .desktop file -- the icon quietly reverts to the generic Wayland
 * one, with nothing in any log to say why. Rather than restate the slug in
 * desktop.nix and hope, the identity is re-derived here with the exact algorithm
 * the shipped Electron runs, and the .desktop file, its StartupWMClass and its
 * Icon= are checked against the value that comes out. A drift in either
 * direction fails the build and names both sides.
 *
 * Algorithm and wiring, read from Electron v44.3.0:
 *   lib/browser/init.ts:136        app.setDesktopName(packageJson.desktopName || defaultDesktopName(app.name))
 *   lib/browser/init.ts:130-134    app.name = packageJson.productName ?? packageJson.name, trimmed
 *   lib/browser/desktop-name.ts    the slug, and the "<exe>.desktop" fallback
 *   shell/browser/api/electron_api_app.cc:974  SetDesktopName writes CHROME_DESKTOP
 *   shell/common/platform_util_linux.cc:471    GetXdgAppId strips a ".desktop" suffix
 *   shell/browser/native_window_views.cc:321   WM_CLASS and the Wayland app id
 *                                              are set from that one value
 *
 * Verified against a running window on niri 25.x: the shipped 0.2.1-alpha.1
 * tree reports app_id "deepseek-ai-dsh-desktop", which is what deriveAppId()
 * returns for its manifest.
 */
import { existsSync, readFileSync } from "node:fs"
import { basename, join } from "node:path"

const [, , appRoot, outputRoot, expectedId, iconName] = process.argv
if ([appRoot, outputRoot, expectedId, iconName].some(value => value === undefined)) {
  console.error("usage: desktop-identity.mjs <app-root> <output-root> <expected-desktop-id> <icon-theme-name>")
  process.exit(2)
}

/** Electron's defaultDesktopName() (lib/browser/desktop-name.ts). */
function defaultDesktopName(name) {
  // NFKD decomposes accented characters; \p{M} drops the combining marks.
  const slug = name
    && name
      .normalize("NFKD")
      .replace(/\p{M}/gu, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
  return slug ? `${slug}.desktop` : `${basename(process.execPath)}.desktop`
}

/**
 * The app id Electron gives this application, from its shipped manifest.
 * @param {Record<string, unknown>} manifest - resources/app/package.json.
 * @returns {string} app id: the .desktop name without its suffix.
 */
function deriveAppId(manifest) {
  // init.ts:130-134. `!= null` and `.trim()` mirror the source exactly: an
  // empty productName still wins over name, and the trimmed form is what the
  // slug is taken from.
  let appName
  if (manifest.productName != null) appName = `${manifest.productName}`.trim()
  else if (manifest.name != null) appName = `${manifest.name}`.trim()

  // init.ts:136. `||`, not `??`: an empty desktopName falls through to the slug.
  const desktopName = manifest.desktopName || defaultDesktopName(appName)
  // platform_util_linux.cc:471 -- the id is the desktop file name minus the suffix.
  return String(desktopName).endsWith(".desktop")
    ? String(desktopName).slice(0, -".desktop".length)
    : String(desktopName)
}

const manifestPath = join(appRoot, "package.json")
if (!existsSync(manifestPath)) {
  console.error(`desktop identity: no application manifest at ${manifestPath}`)
  process.exit(1)
}
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"))
const derivedId = deriveAppId(manifest)

if (derivedId !== expectedId) {
  console.error(`desktop identity: the app id Electron derives is "${derivedId}", but this package publishes "${expectedId}"`)
  console.error(`desktop identity:   manifest     ${manifestPath}`)
  console.error(`desktop identity:   name         ${JSON.stringify(manifest.name)}`)
  console.error(`desktop identity:   productName  ${JSON.stringify(manifest.productName)}`)
  console.error(`desktop identity:   desktopName  ${JSON.stringify(manifest.desktopName)}`)
  console.error("desktop identity: the window would no longer match the installed .desktop file, and a Wayland")
  console.error("desktop identity: task bar would fall back to its generic icon. Upstream renamed the package:")
  console.error(`desktop identity: move desktopId in desktop.nix to "${derivedId}" (and rename the desktop entry),`)
  console.error("desktop identity: or pin the identity by adding a desktopName field to the app manifest.")
  process.exit(1)
}

const desktopFile = join(outputRoot, "share", "applications", `${expectedId}.desktop`)
if (!existsSync(desktopFile)) {
  console.error(`desktop identity: ${desktopFile} is missing; the shell looks a window up by that exact file name`)
  process.exit(1)
}

/** One `Key=value` line out of a desktop entry. */
function readKey(body, key) {
  const match = body.match(new RegExp(`^${key}=(.*)$`, "m"))
  return match === null ? undefined : match[1]
}

const entry = readFileSync(desktopFile, "utf8")
const problems = []
const startupWMClass = readKey(entry, "StartupWMClass")
if (startupWMClass !== expectedId) {
  problems.push(`StartupWMClass=${startupWMClass} does not match the app id "${expectedId}" (X11 WM_CLASS)`)
}
const icon = readKey(entry, "Icon")
if (icon !== iconName) {
  problems.push(`Icon=${icon} does not match the installed icon theme name "${iconName}"`)
}
// The two lookups the desktop file's Icon= feeds: the raster the window and
// tray also use, and the vector original for launchers that scale.
const raster = join(outputRoot, "share", "icons", "hicolor", "512x512", "apps", `${iconName}.png`)
const vector = join(outputRoot, "share", "icons", "hicolor", "scalable", "apps", `${iconName}.svg`)
if (!existsSync(raster)) problems.push(`no icon at ${raster}`)
if (!existsSync(vector)) problems.push(`no icon at ${vector}`)

if (problems.length > 0) {
  console.error(problems.map(line => `desktop identity: ${line}`).join("\n"))
  process.exit(1)
}

console.log(`  ok: desktop identity ${expectedId} matches the app id Electron derives, its .desktop file, StartupWMClass and both icons`)
