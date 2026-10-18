#!/usr/bin/env node
/**
 * Localize the Desktop menus on Linux.
 *
 * The shell keeps a two-language message table (`en` and `zh`) and drives its
 * own menu items from `currentDesktopLocale().messages`: the application menu,
 * the About/Check-updates entries, the tray menu and the quit dialog all follow
 * the locale. Three places do not, and on Linux all three end up in English
 * even when the locale resolves to zh-CN:
 *
 *   1. The standard Edit menu. Non-darwin builds ask Electron for
 *      `{ role: "editMenu" }` and let it fill in Undo/Redo/Cut/Copy/Paste/
 *      Delete/Select All. Electron takes those labels from its own resources
 *      and never localizes them on Linux, so the menu reads English while the
 *      "Application" menu next to it reads 应用. macOS is unaffected -- AppKit
 *      localizes the standard menu through the system language -- and is left
 *      alone here.
 *
 *   2. The right-click menu. The `context-menu` handler already localizes role
 *      labels, but only under `process.platform === "win32"`. Linux falls
 *      through to the bare roles and shows Undo/Redo/Cut/Copy/Paste/Select All
 *      in English.
 *
 *   3. The application menu's quit item. It carries an explicit label on
 *      macOS and Windows; on Linux the label is omitted, so the bare
 *      `{ role: "quit" }` renders as "Quit" whatever the locale.
 *
 * Each replacement spells the items out with an explicit `label` taken from
 * `currentDesktopLocale().messages` while keeping the native `role`, so
 * behaviour, enabled state and the default accelerators are exactly those
 * Electron provides. Labels always come from the dictionary, never from a
 * hardcoded string: `currentDesktopLocale()` resolves to the `en` table for
 * every locale that does not start with `zh`, so an English session shows
 * "Edit"/"Undo"/... and never Chinese, and `refreshApplicationMenu()` builds
 * the template per call, so a locale change re-labels the menu instead of
 * leaving it stale.
 *
 * The templates are built inside the same expressions that read the locale
 * today -- `platformMenus()` for the Edit menu, the `context-menu` handler for
 * the popup -- rather than hoisted to module scope, for that reason.
 *
 * Each patch replaces one exact anchor verified to occur exactly once in the
 * 0.2.1-rc.2 bundle. When an upstream bump localizes the menus itself, or
 * moves the code, the count check fails this build and names the patch instead
 * of shipping a silently half-localized shell. The rewritten bundle is
 * syntax-checked as an ES module before the script exits.
 */
import { spawnSync } from "node:child_process"
import { readFileSync, writeFileSync } from "node:fs"

const [, , mainPath] = process.argv
if (mainPath === undefined) {
  console.error("usage: desktop-menu-locale.mjs <path/to/lib/main.js>")
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

// One indented line per Edit item, in the order Electron's own editMenu uses
// (undo, redo, separator, cut, copy, paste, delete, separator, selectAll).
// Keeping the roles is what preserves the native behaviour and accelerators;
// only the labels differ from the stock menu.
const editItem = (role, key) =>
  `\t\t\t{ role: "${role}", label: currentDesktopLocale().messages.${key} },\n`

const patches = [
  {
    name: "localize-edit-menu-linux",
    why: "label the standard Edit menu from the locale table, which Electron does not do on Linux",
    anchor:
      "\tconst platformMenus = () => darwin ? [\n"
      + "\t\tshortcuts.fileMenu(currentDesktopLocale().messages),\n"
      + "\t\t{ role: \"editMenu\" },\n"
      + "\t\t{ role: \"windowMenu\" }\n"
      + "\t] : [{ role: \"editMenu\" }];",
    replacement:
      "\t// [dsh-desktop] macOS gets the standard Edit menu labels from AppKit; Electron on Linux\n"
      + "\t// renders them in English whatever the locale. The Linux branch spells the items out and\n"
      + "\t// keeps the native roles, which is what preserves behaviour and the default accelerators;\n"
      + "\t// only the labels differ. Built per call, so refreshApplicationMenu() re-labels the menu\n"
      + "\t// when the locale changes instead of leaving the previous language in place.\n"
      + "\tconst platformMenus = () => darwin ? [\n"
      + "\t\tshortcuts.fileMenu(currentDesktopLocale().messages),\n"
      + "\t\t{ role: \"editMenu\" },\n"
      + "\t\t{ role: \"windowMenu\" }\n"
      + "\t] : process.platform === \"linux\" ? [{\n"
      + "\t\tlabel: currentDesktopLocale().messages.edit,\n"
      + "\t\tsubmenu: [\n"
      + editItem("undo", "undo")
      + editItem("redo", "redo")
      + "\t\t\t{ type: \"separator\" },\n"
      + editItem("cut", "cut")
      + editItem("copy", "copy")
      + editItem("paste", "paste")
      + editItem("delete", "delete")
      + "\t\t\t{ type: \"separator\" },\n"
      + editItem("selectAll", "selectAll")
      + "\t\t]\n"
      + "\t}] : [{ role: \"editMenu\" }];",
  },
  {
    name: "localize-context-menu-linux",
    why: "localize the right-click menu on Linux, where it fell through to English role labels",
    anchor:
      "\t\t\t\t...process.platform === \"win32\" && item.role !== void 0 && item.role in messages ? { label: messages[item.role] } : {},",
    replacement:
      "\t\t\t\t// [dsh-desktop] Keep the win32 behaviour and extend it to Linux, which showed the\n"
      + "\t\t\t\t// English role labels. macOS localizes native menu items through AppKit itself, so\n"
      + "\t\t\t\t// it keeps the bare roles rather than a hand-written label.\n"
      + "\t\t\t\t...process.platform !== \"darwin\" && item.role !== void 0 && item.role in messages ? { label: messages[item.role] } : {},",
  },
  {
    name: "localize-quit-item-linux",
    why: "give the Linux application menu's quit item an explicit label instead of Electron's English \"Quit\"",
    anchor:
      "...darwin ? { label: currentDesktopLocale().messages.quitApplication } : process.platform === \"win32\" ? { label: currentDesktopLocale().messages.exitApplication } : {}",
    replacement:
      "...darwin ? { label: currentDesktopLocale().messages.quitApplication } : process.platform === \"win32\" ? { label: currentDesktopLocale().messages.exitApplication } : { label: currentDesktopLocale().messages.quitApplication }",
  },
]

let output = readFileSync(mainPath, "utf8")
for (const patch of patches) {
  const count = countOccurrences(output, patch.anchor)
  if (count !== 1) {
    console.error(`desktop menu locale: anchor for ${patch.name} matches ${count} times, expected exactly once`)
    console.error(`desktop menu locale: ${patch.why}`)
    console.error("desktop menu locale: upstream moved this code; re-verify the patch against the new bundle")
    process.exit(1)
  }
  output = output.replace(patch.anchor, patch.replacement)
}
writeFileSync(mainPath, output)

// The file ships as an ES module (the application manifest is "type": "module"),
// so --check parses it as one and catches any mistake in the inserted code.
const check = spawnSync(process.execPath, ["--check", mainPath], { encoding: "utf8" })
if (check.status !== 0) {
  console.error("desktop menu locale: the patched bundle does not parse:")
  console.error(check.stderr || check.stdout)
  process.exit(1)
}
console.log(`desktop menu locale: applied ${patches.length} patches to ${mainPath}`)
