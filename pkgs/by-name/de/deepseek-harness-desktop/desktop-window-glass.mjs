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
 *      The pinned control overlays are the second half. The composer seat, the
 *      two plugin page headers and the expanded reasoning header all sit above
 *      scrolling content and upstream hides that content with an opaque
 *      var(--dsw-alias-bg-base) fill: a 36px fade to solid under the composer,
 *      a scroll-linked ::before under the plugin bar, the sticky market head's
 *      own background, the sticky disclosure header inside an expanded think
 *      row. On darwin the centre column behind them paints the same colour, so
 *      the fill is invisible; over a cleared column it becomes the one opaque
 *      strip left in the interface. The fills are cleared here, but a cleared
 *      fill turns the same area into a window where crisp list text scrolls
 *      under the header text.
 *
 *      The obvious answer, a backdrop blur on each overlay, does not work in
 *      this window. Chromium only applies backdrop-filter where the backdrop it
 *      samples is opaque; a transparent Electron window keeps the page's
 *      background transparent too, so the filter is a no-op and the text stays
 *      crisp. (Verified against a real window over the live wallpaper: the same
 *      overlay blurs instantly once the content behind it paints an opaque
 *      background, and no combination of a translucent window background, a
 *      translucent CSS root, or `isolation` brings the filter back.) The
 *      treatment here therefore works on the content instead of on the glass:
 *
 *      All four overlays fade their content instead of filling. A small script
 *      (glassFadeScript below) masks the content that scrolls under each overlay
 *      with a linear gradient band: on every scroll frame it measures the
 *      overlay's edge in viewport space and writes the band's two stops in the
 *      masked element's own coordinates, so the fade stays pinned under the
 *      overlay while the content moves. The mask covers the whole element, so
 *      only the band fades and everything beyond it stays untouched. The two
 *      plugin page headers come first: the market head's content boxes are
 *      masked below the head's own bottom edge, and the plugin bar's around the
 *      bar's compact height, because that is the band it actually paints - its
 *      head clips to --plugin-header-paint-height, so the boundary sits there
 *      rather than at the bar box's full height. The expanded think row's
 *      disclosure header works the same way once it sticks: the header and the
 *      prose are siblings, so the prose is masked against the header's bottom
 *      edge, faded over a longer 48px band below it so the transition is visible
 *      under a header this short. No DOM is reparented, so each component's own
 *      scrolling layout keeps working.
 *
 *      The composer seat masks the same way: the transcript's message column is
 *      a sibling of the seat, so it is masked against the seat's top edge - the
 *      prose fades out over 48px above the composer and is hidden underneath it,
 *      which is what the seat's own solid gradient used to do. That boundary
 *      follows the composer's height rather than the scroll, so the script also
 *      re-measures it through a ResizeObserver.
 *
 *      prefers-reduced-transparency: reduce hands upstream's solid fills back
 *      along with the rest of the fallback and drops the masks, so the reduced
 *      path never shows header text on top of the list.
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
 * Anchors are exact substrings checked to occur exactly once in the 0.2.2-alpha.2
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
  // The composer seat hides the transcript scrolling under the input card with a
  // fixed 36px fade to solid --dsw-alias-bg-base; on darwin the column beneath
  // paints the same colour, so the fill is invisible, and over a cleared column
  // it is an opaque slab. The fill is cleared here and the prose is faded out
  // above the seat by the mask rules and script below, so the transcript
  // dissolves into the composer instead of running under a band.
  "html[data-platform='linux'] [data-phase='active'] [class*='composerSeat'],html[data-platform='linux'] [data-content-phase='active'] [class*='composerSeat']{background:none}",
  // The expanded think row's disclosure header sticks over the prose it belongs
  // to and upstream masks that prose with a solid fill. The fill is cleared here
  // and the prose is faded out under the header by the mask rules and script
  // below - a translucent scrim was tried first and reads as a dark band once
  // the theme goes dark, while a mask hides the prose outright.
  "html[data-platform='linux'] [data-expanded] [data-open] [data-disclosure-header]{background:transparent}",
  // The two scroll-sticky page headers upstream paints in --dsw-alias-bg-base:
  // the plugin manager's page-bar ::before and the market page's sticky head.
  // Both fills are cleared - the glass runs from the title bar down - and the
  // content scrolling under them is faded out by the mask rules and script
  // below instead, so no list text reaches the header band.
  "html[data-platform='linux'] [class*='pageBar']::before,html[data-platform='linux'] [class*='stickyHead']{background:transparent}",
  // Content fade under every pinned overlay. The script measures the gradient
  // band against the overlay's edge in viewport space on each scroll frame and
  // writes the two stops in the masked element's own coordinates, so the fade
  // stays pinned under the overlay while the content moves. The mask covers the
  // element's whole box, so there is no image edge: stops run transparent ->
  // black where the content is hidden above the boundary (the headers), and
  // black -> transparent where it is hidden below it (the composer).
  "html[data-platform='linux'] [data-dsh-glass-fade]{mask-image:linear-gradient(to bottom,rgba(0,0,0,0) var(--dsh-glass-stop0),#000 var(--dsh-glass-stop1))}",
  "html[data-platform='linux'] [data-dsh-glass-fade='bottom']{mask-image:linear-gradient(to bottom,#000 var(--dsh-glass-stop0),rgba(0,0,0,0) var(--dsh-glass-stop1))}",
  "@media (prefers-reduced-transparency:reduce){html[data-platform='linux'] #root > [data-slot=root] > div{background:var(--dsw-alias-bg-base)}}",
  // With the frame opaque again the overlays take upstream's own solid fills and
  // the masks are dropped, so the reduce path matches upstream exactly.
  "@media (prefers-reduced-transparency:reduce){html[data-platform='linux'] [data-phase='active'] [class*='composerSeat'],html[data-platform='linux'] [data-content-phase='active'] [class*='composerSeat']{background:linear-gradient(180deg,color-mix(in srgb,var(--dsw-alias-bg-base) 0%,transparent) 0px,var(--dsw-alias-bg-base) 36px)}}",
  "@media (prefers-reduced-transparency:reduce){html[data-platform='linux'] [data-expanded] [data-open] [data-disclosure-header]{background:var(--dsw-alias-bg-base)}}",
  "@media (prefers-reduced-transparency:reduce){html[data-platform='linux'] [class*='pageBar']::before,html[data-platform='linux'] [class*='stickyHead']{background:var(--dsw-alias-bg-base)}}",
  "@media (prefers-reduced-transparency:reduce){html[data-platform='linux'] [data-dsh-glass-fade]{mask-image:none}}",
].join("")

// Every fade band is anchored to a pinned overlay's edge in viewport space, so
// a plain CSS mask cannot express it: the mask image moves with the element, and
// the band would drift with the content. This script only measures. For each
// pinned overlay - the two plugin page headers, the expanded think row's
// disclosure header, the composer seat - it masks the content that scrolls under
// the overlay with a linear gradient band re-measured against the overlay's edge
// on every scroll frame, and writes the band's two stops in the masked element's
// own coordinates. The mask covers the whole element, so only the band fades and
// everything beyond it stays untouched. No node is moved or reparented, and the
// platform guard keeps the script inert in the shell renderers, where
// data-platform is absent.
const glassFadeScript = `
;(() => {
  if (globalThis.__dshDesktopGlassFade) return
  globalThis.__dshDesktopGlassFade = true
  const PAGE_FADE = 28
  const BODY_FADE = 48
  const OVERLAY = '[class*="stickyHead"],[class*="pageBar"]'
  const REASONING = '[data-expanded] [data-open] [data-disclosure-header]'
  const COMPOSER = '[class*="composerSeat"]'
  const FLOW = '[data-chat-flow]'
  const masked = new Set()
  const geometry = new WeakMap()
  const scrollers = new WeakMap()
  const watched = new WeakSet()
  let scheduled = false

  function platformLinux() {
    return document.documentElement.getAttribute('data-platform') === 'linux'
  }
  function pad(value) {
    const n = parseFloat(value)
    return Number.isFinite(n) ? n : 0
  }
  function schedule() {
    if (scheduled) return
    scheduled = true
    requestAnimationFrame(() => { scheduled = false; sync() })
  }
  const resizes = new ResizeObserver(() => schedule())
  function watch(element) {
    if (watched.has(element)) return
    watched.add(element)
    resizes.observe(element)
  }
  function scrollParent(node) {
    let el = node.parentElement
    while (el && el !== document.documentElement) {
      if (/(auto|scroll)/.test(getComputedStyle(el).overflowY)) return el
      el = el.parentElement
    }
    return null
  }
  function scrollerOf(header) {
    const cached = scrollers.get(header)
    if (cached && cached.isConnected && cached.contains(header)) return cached
    const found = scrollParent(header)
    if (found) scrollers.set(header, found)
    return found
  }
  function release(element) {
    if (!masked.delete(element)) return
    element.removeAttribute('data-dsh-glass-fade')
    element.style.removeProperty('--dsh-glass-stop0')
    element.style.removeProperty('--dsh-glass-stop1')
    geometry.delete(element)
  }
  function mask(element, boundary, fade, mode, keep) {
    const rect = element.getBoundingClientRect()
    if (rect.height < 1) return
    const local = boundary - rect.top
    const below = mode === 'below'
    const reversed = mode === 'bottom'
    const stop0 = below ? local : local - fade
    const stop1 = below ? local + fade : local
    const key = stop0 + '|' + stop1 + (reversed ? '|b' : '|a')
    keep.add(element)
    if (geometry.get(element) === key) return
    geometry.set(element, key)
    element.setAttribute('data-dsh-glass-fade', reversed ? 'bottom' : '')
    element.style.setProperty('--dsh-glass-stop0', stop0 + 'px')
    element.style.setProperty('--dsh-glass-stop1', stop1 + 'px')
    masked.add(element)
  }
  function syncPageHeaders(keep) {
    for (const overlay of document.querySelectorAll(OVERLAY)) {
      const body = overlay.parentElement
      if (!body || !body.isConnected) continue
      if (!/(auto|scroll)/.test(getComputedStyle(body).overflowY)) continue
      const rect = overlay.getBoundingClientRect()
      const isBar = overlay.matches('[class*="pageBar"]')
      const compact = isBar ? pad(getComputedStyle(overlay).getPropertyValue('--plugin-header-compact-height')) : 0
      const boundary = isBar && compact > 0 ? rect.top + compact : rect.bottom
      for (const child of body.children) {
        if (child === overlay || child.matches(OVERLAY)) continue
        mask(child, boundary, PAGE_FADE, isBar ? 'below' : 'above', keep)
      }
    }
  }
  function syncReasoning(keep) {
    for (const header of document.querySelectorAll(REASONING)) {
      const root = header.parentElement
      if (!root) continue
      const scroller = scrollerOf(header)
      if (!scroller) continue
      const hr = header.getBoundingClientRect()
      if (hr.height < 1) continue
      const boundary = scroller.getBoundingClientRect().top + hr.height
      for (const child of root.children) {
        if (child === header) continue
        mask(child, boundary, BODY_FADE, 'below', keep)
      }
    }
  }
  function syncComposer(keep) {
    for (const seat of document.querySelectorAll(COMPOSER)) {
      const body = seat.parentElement
      if (!body || !body.isConnected) continue
      if (!/(auto|scroll)/.test(getComputedStyle(body).overflowY)) continue
      watch(seat)
      const boundary = seat.getBoundingClientRect().top
      for (const flow of body.querySelectorAll(FLOW)) {
        watch(flow)
        mask(flow, boundary, BODY_FADE, 'bottom', keep)
      }
    }
  }
  function sync() {
    if (!platformLinux()) return
    const keep = new Set()
    syncPageHeaders(keep)
    syncReasoning(keep)
    syncComposer(keep)
    for (const element of masked) {
      if (!keep.has(element) || !element.isConnected) release(element)
    }
  }
  addEventListener('scroll', schedule, true)
  addEventListener('resize', schedule)
  new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true })
  new MutationObserver(schedule).observe(document.documentElement, { attributes: true, attributeFilter: ['data-platform'] })
  schedule()
})()

`

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
    why: "stop the document, the sidebar column, the conversation root and the pinned overlay fills from painting over the blurred backdrop",
    anchor:
      "\tconst content = pathname === \"/\" || pathname === \"/index.html\" ? body.toString().replace(\"<head>\", \"<head><script>globalThis.__DSH_BOOT_READY__ = Promise.withResolvers()<\\/script>\") : new Uint8Array(body);",
    replacement:
      "\t// [dsh-desktop] The packaged Web UI clears these surfaces for darwin only, so on Linux\n"
      + "\t// the window keeps painting opaque backgrounds over the compositor's blur. The rules\n"
      + "\t// are scoped to data-platform=linux, which only the application window's preload\n"
      + "\t// sets, so the dsh-app://shell renderer pages are left untouched.\n"
      + "\tconst glassStyle = \"<style>" + glassCss + "</style>\";\n"
      + "\t// [dsh-desktop] Fade content out under the pinned plugin page headers; the headers'\n"
      + "\t// opaque fills are cleared by the style sheet and this mask is what keeps the list\n"
      + "\t// from scrolling out from under the header text.\n"
      + "\tconst glassScript = `<script>" + glassFadeScript + "<\\/script>`;\n"
      + "\tconst content = pathname === \"/\" || pathname === \"/index.html\" ? body.toString().replace(\"<head>\", `<head>${glassStyle}${glassScript}<script>globalThis.__DSH_BOOT_READY__ = Promise.withResolvers()<\\/script>`) : new Uint8Array(body);",
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
