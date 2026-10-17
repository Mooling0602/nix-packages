#!/usr/bin/env node
/**
 * Give the Linux window the same glass treatment upstream implements for macOS.
 *
 * A compositor blurs the wallpaper behind a window, and that blur shows only
 * where the window's own surface is transparent. Upstream arranges for this on
 * darwin only: createWindow spreads `vibrancy: "sidebar"` and a transparent
 * `backgroundColor`, the packaged Web UI clears the document background under
 * `html[data-platform=darwin]`, and the preload marks the document root with
 * `process.platform`. Each patch below supplies the Linux half of one of those:
 *
 *   1. The window material. Without `transparent` Electron hands the compositor
 *      an opaque surface that no page styling can reveal, and it offers no
 *      vibrancy or backgroundMaterial on Linux.
 *
 *   2. The document rule. The bundle serves its own index.html from
 *      serveWebDocument(), which already injects the __DSH_BOOT_READY__ script
 *      into <head>; the same injection carries the style sheet in glassCss
 *      below. Three of its rules clear a surface that paints an opaque
 *      background of its own and would otherwise cover the backdrop entirely:
 *      the document, the sidebar column together with the
 *      --dsw-specific-sidebar-fill token its inner surface consumes, and the
 *      conversation root. The frame element instead keeps a translucent tint of
 *      var(--dsw-alias-bg-base), because a fully cleared frame leaves text
 *      illegible over a busy wallpaper. That is the Linux form of the rules the
 *      packaged Web UI ships for darwin, and it is what makes this patch
 *      disappear if any one surface is missed: a single opaque layer is enough
 *      to hide the blur. Content is left alone, so cards and menus keep their
 *      own backgrounds and the glass shows around the interface.
 *
 *      One surface needs more than a cleared background. The composer seat hides
 *      the transcript scrolling under the input card by fading to solid
 *      var(--dsw-alias-bg-base). On darwin that fill is invisible because the
 *      column beneath paints the same colour; over a cleared column it becomes an
 *      opaque frame around the input card. The seat is cleared as well, and only
 *      cleared: a translucent scrim still reads as a band, and a masked backdrop
 *      blur is worse, because on a transparent window the blur samples the
 *      window's own transparency as opaque black and the band turns into a
 *      smeared black halo. What the fill used to mask stays masked anyway, by the
 *      card itself: it is wider than the transcript column and paints its own
 *      opaque --dsw-specific-input-major.
 *
 *      Injecting here beats editing the dist directly: those files are upstream
 *      build output whose names carry content hashes, and the shell's document
 *      handler is reached wherever the frontend is served from.
 *
 *      The selectors read two things the bundle keeps stable while its hashed
 *      class names change: CSS-module local names, which survive as a substring
 *      (`[class*='sidebarCol']` works whether the emitted class is x_Ggxa_frame
 *      or _frame_1hfzl_1, and this build carries both schemes at once), and
 *      structural attributes on the frame element. Every rule wins on
 *      specificity alone; none needs !important.
 *
 *      prefers-reduced-transparency: reduce restores an opaque frame, the same
 *      fallback upstream ships. The cleared surfaces then simply show it.
 *
 * The rule is inert elsewhere by construction. Only the application window's
 * preload calls markDocumentPlatform(), so the renderer pages served from
 * dsh-app://shell/* (welcome, update dialog, mandatory update) never match the
 * selector and keep their own opaque background.
 *
 * Neither patch changes a platform value. `process.platform` keeps returning
 * "linux" and the preload keeps marking the document `data-platform=linux`, so
 * the packaged Web UI's `html[data-platform=darwin]` rules stay off on Linux;
 * they scope the window-drag regions, the menu backing element and the title
 * bar adjustments, and none of that changes here.
 *
 * Anchors are exact substrings checked to occur exactly once in the 0.2.1-alpha.4
 * bundle. An upstream bump that moves one fails the build naming the patch,
 * instead of shipping a half-glazed window.
 */
import { spawnSync } from "node:child_process"
import { readFileSync, writeFileSync } from "node:fs"

const [, , mainPath] = process.argv
if (mainPath === undefined) {
  console.error("usage: desktop-window-glass.mjs <path/to/lib/main.js>")
  process.exit(2)
}

/** Plain indexOf rather than a regex, so anchors are matched literally. */
function countOccurrences(text, needle) {
  let count = 0
  let at = text.indexOf(needle)
  while (at !== -1) {
    count += 1
    at = text.indexOf(needle, at + needle.length)
  }
  return count
}

// Single quotes around the attribute values keep every rule a plain
// double-quoted JS string, so the pieces below need no escaping.
const glassCss = [
  "html[data-platform='linux'],html[data-platform='linux'] body{background:transparent}",
  "html[data-platform='linux'] #root > [data-slot=root] > div{background:color-mix(in srgb,var(--dsw-alias-bg-base) 72%,transparent)}",
  "html[data-platform='linux'] [class*='sidebarCol']{background:transparent;--dsw-specific-sidebar-fill:transparent}",
  "html[data-platform='linux'] [data-slot='main.conversation'] > div{background:transparent}",
  // The composer seat fades the transcript out under the input card: a fixed
  // 36px band where a solid --dsw-alias-bg-base gradient wipes the text out, then
  // solid below. On darwin the column beneath already paints that colour, so the
  // fill is invisible; over a cleared column it is an opaque slab with a soft top
  // edge, which is what reads as a black band around the input card. The seat
  // keeps no fill at all here. A translucent fill or a masked backdrop blur both
  // look wrong on a transparent window: the blur samples the window's own
  // transparency as opaque black, so the band turns into a smeared black halo
  // instead of glass. Clearing the fill leaves the seat transparent, which is the
  // only treatment that matches the cleared column around it. The transcript can
  // then reach the card's own edge, but the card is wider than the text column
  // (--dsh-composer-card-max-width is --dsh-chat-content-width plus the side
  // clearance), so the text stays behind the card's opaque
  // --dsw-specific-input-major background.
  "html[data-platform='linux'] body #root [class*='composerSeat']{background:none}",
  "@media (prefers-reduced-transparency:reduce){html[data-platform='linux'] #root > [data-slot=root] > div{background:var(--dsw-alias-bg-base)}}",
  // An opaque frame restores the column the fill was written against; hand the
  // seat back unchanged so the reduced-transparency path matches upstream.
  "@media (prefers-reduced-transparency:reduce){html[data-platform='linux'] body #root [class*='composerSeat']{background:linear-gradient(180deg,transparent 0px,var(--dsw-alias-bg-base) 36px)}}",
].join("")

const patches = [
  {
    name: "window-material-linux",
    why: "give the Linux main window a transparent surface, the counterpart of the darwin vibrancy spread",
    anchor: "\t\t...process.platform === \"darwin\" ? {",
    replacement:
      "\t\t// [dsh-desktop] On Linux the window is transparent instead: the page clears its own\n"
      + "\t\t// background (patch in serveWebDocument below) and the compositor blurs what shows\n"
      + "\t\t// through. transparent: true is what makes Electron hand the compositor an alpha\n"
      + "\t\t// surface at all; Electron has no vibrancy or backgroundMaterial on Linux.\n"
      + "\t\t...process.platform === \"linux\" ? {\n"
      + "\t\t\ttransparent: true,\n"
      + "\t\t\tbackgroundColor: \"#00000000\"\n"
      + "\t\t} : {},\n"
      + "\t\t...process.platform === \"darwin\" ? {",
  },
  {
    name: "document-background-linux",
    why: "stop the document, the sidebar column and the conversation root from painting over the blurred backdrop",
    anchor:
      "\tconst content = pathname === \"/\" || pathname === \"/index.html\" ? body.toString().replace(\"<head>\", \"<head><script>globalThis.__DSH_BOOT_READY__ = Promise.withResolvers()<\\/script>\") : new Uint8Array(body);",
    replacement:
      "\t// [dsh-desktop] The packaged Web UI clears these surfaces for darwin only, so on Linux\n"
      + "\t// the window keeps painting opaque backgrounds over the compositor's blur. The rules\n"
      + "\t// are scoped to data-platform=linux, which only the application window's preload\n"
      + "\t// sets, so the dsh-app://shell renderer pages are left untouched.\n"
      + "\tconst glassStyle = \"<style>" + glassCss + "</style>\";\n"
      + "\tconst content = pathname === \"/\" || pathname === \"/index.html\" ? body.toString().replace(\"<head>\", `<head>${glassStyle}<script>globalThis.__DSH_BOOT_READY__ = Promise.withResolvers()<\\/script>`) : new Uint8Array(body);",
  },
]

let output = readFileSync(mainPath, "utf8")
for (const patch of patches) {
  const count = countOccurrences(output, patch.anchor)
  if (count !== 1) {
    console.error(`desktop window glass: anchor for ${patch.name} matches ${count} times, expected exactly once`)
    console.error(`desktop window glass: ${patch.why}`)
    console.error("desktop window glass: upstream moved this code; re-verify the patch against the new bundle")
    process.exit(1)
  }
  output = output.replace(patch.anchor, patch.replacement)
}
writeFileSync(mainPath, output)

// The file ships as an ES module (the application manifest is "type": "module"),
// so --check parses it as one and catches a syntax error in the inserted code.
const check = spawnSync(process.execPath, ["--check", mainPath], { encoding: "utf8" })
if (check.status !== 0) {
  console.error("desktop window glass: the patched bundle does not parse:")
  console.error(check.stderr || check.stdout)
  process.exit(1)
}
console.log(`desktop window glass: applied ${patches.length} patches to ${mainPath}`)
