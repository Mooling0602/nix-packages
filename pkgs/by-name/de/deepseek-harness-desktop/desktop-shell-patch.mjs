#!/usr/bin/env node
/**
 * Apply the three Desktop shell patches to the bundled main process.
 *
 * The desktop package assembles the unmodified upstream build; it does not
 * re-run TypeScript or tsdown. Four Linux behaviours upstream gates on
 * win32 (or does not expose at all) are therefore patched into the shipped
 * bundle, `resources/app/lib/main.js`, at install time. The upstream sources
 * are never touched, and the bundle is the only file rewritten.
 *
 *   1. Tray icon on Linux. Upstream creates DesktopTray on Windows only and
 *      points it at the multi-size ICO `resources/tray.ico`. Linux gets the
 *      same tray (click reopens the window, context menu offers Open/Quit),
 *      fed with the PNG application icon: nativeImage decodes PNG and JPEG
 *      only (https://www.electronjs.org/docs/latest/api/native-image), so the
 *      ICO cannot load there. The Linux tray registers over
 *      StatusNotifierItem like every Electron tray on Linux
 *      (https://www.electronjs.org/docs/latest/api/tray), so no extra library
 *      is involved -- Electron implements the protocol itself.
 *
 *   2. Background-close notice on Linux. Upstream shows the one-time "you can
 *      reopen the window from the system tray" confirmation on Windows only.
 *      Closing the window on Linux already hides it (the page and Host keep
 *      running) and with patch 1 the tray is the way back, so the notice now
 *      describes the Linux behaviour exactly and is enabled there too.
 *
 *   3. Menu bar hidden by default. Linux shows the application menu as a menu
 *      bar in every BrowserWindow. DSH_DESKTOP_HIDE_MENUBAR=1 (the default)
 *      hides it via setMenuBarVisibility -- which keeps the application menu
 *      and its accelerators (Edit menu, F12 dev tools) alive -- and =0 shows
 *      it. Upstream exposes no control for this (setMenuBarVisibility and
 *      setAutoHideMenuBar appear nowhere in the shell), hence the environment
 *      variable. The state is applied once per window creation and re-applied
 *      after every application-menu rebuild, because replacing the menu is the
 *      one operation that can restore the bar's default visibility.
 *
 *   4. Graceful shutdown on SIGINT/SIGTERM, and a Host process group of its
 *      own. Adapted from Moraxyc/deepseek-harness.nix
 *      (desktop-signal-shutdown.patch, commit c9999f4): without a handler the
 *      process dies on the signal mid-run -- no quit path, no Host teardown --
 *      and a terminal Ctrl+C reaches the Host through the shared process
 *      group, cutting it down outside its IPC shutdown. The fix quits through
 *      the application's own no-confirmation path, skips main() when the
 *      signal beat startup, and spawns the Host detached on Linux so terminal
 *      signals belong to the shell alone. Drop it once upstream routes Linux
 *      terminal signals through graceful shutdown and isolates the Host.
 *
 * Each patch replaces one exact anchor that was verified to occur exactly once
 * in the 0.2.0-rc.2 bundle. When an upstream bump moves the code, the count
 * check fails this build and names the patch, instead of shipping a silently
 * half-patched shell. The rewritten bundle is syntax-checked as an ES module
 * before the script exits.
 */
import { spawnSync } from "node:child_process"
import { readFileSync, writeFileSync } from "node:fs"

const [, , mainPath] = process.argv
if (mainPath === undefined) {
  console.error("usage: desktop-shell-patch.mjs <path/to/lib/main.js>")
  process.exit(2)
}

/** Exact-substring occurrence count; plain indexOf, so anchors stay literal. */
function countOccurrences(text, needle) {
  let count = 0
  let at = text.indexOf(needle)
  while (at !== -1) {
    count += 1
    at = text.indexOf(needle, at + needle.length)
  }
  return count
}

const patches = [
  {
    name: "tray-icon-linux",
    why: "create the tray on Linux as well, and feed it the PNG icon (nativeImage reads PNG and JPEG only)",
    anchor:
      "\tconst trayIconPath = development ? join(app.getAppPath(), \"resources\", \"tray-windows.ico\") : join(process.resourcesPath, \"tray.ico\");\n"
      + "\tif (process.platform === \"win32\") try {",
    replacement:
      "\t// [dsh-desktop] Tray on Linux as well, over StatusNotifierItem like every Electron tray there.\n"
      + "\t// nativeImage decodes PNG and JPEG only, so the Windows multi-size ICO cannot feed the icon;\n"
      + "\t// use the PNG application icon, which the packaged layout places at resources/icon.png\n"
      + "\t// (the same file applicationIconPath above hands to the About panel).\n"
      + "\tconst trayIconPath = process.platform === \"linux\"\n"
      + "\t\t? development ? join(app.getAppPath(), \"resources\", \"icon.png\") : join(process.resourcesPath, \"icon.png\")\n"
      + "\t\t: development ? join(app.getAppPath(), \"resources\", \"tray-windows.ico\") : join(process.resourcesPath, \"tray.ico\");\n"
      + "\tif (process.platform === \"win32\" || process.platform === \"linux\") try {",
  },
  {
    name: "background-close-notice-linux",
    why: "show the one-time background-close notice on Linux too, where closing hides the window to the tray",
    anchor: "\tconst backgroundNotice = process.platform === \"win32\" ? new DesktopBackgroundNotice({",
    replacement:
      "\t// [dsh-desktop] On Linux too: closing hides the window to the tray (patch above), so the\n"
      + "\t// one-time notice -- \"You can reopen the window from the system tray\" -- now describes it.\n"
      + "\tconst backgroundNotice = process.platform === \"win32\" || process.platform === \"linux\" ? new DesktopBackgroundNotice({",
  },
  {
    name: "hide-menubar-registration",
    why: "register the DSH_DESKTOP_HIDE_MENUBAR hook at module load, before any window exists",
    anchor: "if (claimDesktopSingleInstance(app, () => {",
    replacement:
      "// [dsh-desktop] DSH_DESKTOP_HIDE_MENUBAR=1 (the default) hides the window menu bar without\n"
      + "// removing the application menu, so its accelerators (Edit menu, F12 dev tools) stay live;\n"
      + "// =0 shows the bar. Upstream exposes no control for this and shows the bar in every window.\n"
      + "// Registered at module load so it covers every window the shell ever creates, including the\n"
      + "// welcome window that main() can open before its own menu setup runs.\n"
      + "app.on(\"browser-window-created\", (_event, window) => {\n"
      + "\tif (process.platform !== \"darwin\") window.setMenuBarVisibility(process.env.DSH_DESKTOP_HIDE_MENUBAR === \"0\");\n"
      + "});\n"
      + "if (claimDesktopSingleInstance(app, () => {",
  },
  {
    name: "hide-menubar-on-menu-rebuild",
    why: "re-apply DSH_DESKTOP_HIDE_MENUBAR after every application-menu rebuild",
    anchor: "\t\ttray?.relabel();",
    replacement:
      "\t\t// [dsh-desktop] Re-apply the DSH_DESKTOP_HIDE_MENUBAR state: replacing the application\n"
      + "\t\t// menu is the one operation that can restore the menu bar's default visibility.\n"
      + "\t\tif (process.platform !== \"darwin\") for (const win of BrowserWindow.getAllWindows()) win.setMenuBarVisibility(process.env.DSH_DESKTOP_HIDE_MENUBAR === \"0\");\n"
      + "\t\ttray?.relabel();",
  },
  {
    name: "signal-shutdown-handler",
    why: "quit through the application's own teardown when Linux sends SIGINT/SIGTERM",
    anchor: "function quitWithoutConfirmation() {\n\tskipQuitConfirmation = true;\n\tapp.quit();\n}",
    replacement:
      "function quitWithoutConfirmation() {\n\tskipQuitConfirmation = true;\n\tapp.quit();\n}\n"
      + "// [dsh-desktop] Quit through the shell's own teardown on SIGINT/SIGTERM (Linux), adapted\n"
      + "// from Moraxyc/deepseek-harness.nix desktop-signal-shutdown.patch (commit c9999f4).\n"
      + "// Without it the signal kills the process with the Host mid-teardown, and once the\n"
      + "// Host is spawned detached (patch below) a signal must still stop the shell itself.\n"
      + "if (process.platform === \"linux\") {\n"
      + "\tconst quitFromSignal = () => {\n"
      + "\t\tif (shuttingDown) return;\n"
      + "\t\tshuttingDown = true;\n"
      + "\t\tquitWithoutConfirmation();\n"
      + "\t};\n"
      + "\tprocess.on(\"SIGINT\", quitFromSignal);\n"
      + "\tprocess.on(\"SIGTERM\", quitFromSignal);\n"
      + "}",
  },
  {
    name: "signal-shutdown-startup-guard",
    why: "do not start main() when a signal already began shutdown during startup",
    anchor: "})) app.whenReady().then(main).catch(async (error) => {",
    replacement:
      "})) app.whenReady().then(async () => {\n"
      + "\tif (!shuttingDown) await main();\n"
      + "}).catch(async (error) => {",
  },
  {
    name: "host-process-detached",
    why: "give the Host its own process group so terminal signals belong to the shell alone",
    anchor: "\t\t], {\n\t\t\tcwd: this.projectDir,\n\t\t\tenv: desktopNodeEnvironment(this.node, void 0, this.environment),",
    replacement:
      "\t\t], {\n"
      + "\t\t\t// [dsh-desktop] Terminal signals belong to the shell; the Host shuts down through\n"
      + "\t\t\t// IPC (Moraxyc/deepseek-harness.nix desktop-signal-shutdown.patch, commit c9999f4).\n"
      + "\t\t\tdetached: process.platform === \"linux\",\n"
      + "\t\t\tcwd: this.projectDir,\n"
      + "\t\t\tenv: desktopNodeEnvironment(this.node, void 0, this.environment),",
  },
]

let output = readFileSync(mainPath, "utf8")
for (const patch of patches) {
  const count = countOccurrences(output, patch.anchor)
  if (count !== 1) {
    console.error(`desktop shell patch: anchor for ${patch.name} matches ${count} times, expected exactly once`)
    console.error(`desktop shell patch: ${patch.why}`)
    console.error("desktop shell patch: upstream moved this code; re-verify the patch against the new bundle")
    process.exit(1)
  }
  output = output.replace(patch.anchor, patch.replacement)
}
writeFileSync(mainPath, output)

// The file ships as an ES module (the application manifest is "type": "module"),
// so --check parses it as one and catches any mistake in the inserted code.
const check = spawnSync(process.execPath, ["--check", mainPath], { encoding: "utf8" })
if (check.status !== 0) {
  console.error("desktop shell patch: the patched bundle does not parse:")
  console.error(check.stderr || check.stdout)
  process.exit(1)
}
console.log(`desktop shell patch: applied ${patches.length} patches to ${mainPath}`)
