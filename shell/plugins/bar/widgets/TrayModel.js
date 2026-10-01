function text(value) {
  return String(value || "").toLowerCase()
}

function itemNamed(item, name) {
  if (!item) return false
  return text(item.id).indexOf(name) !== -1
    || text(item.title).indexOf(name) !== -1
    || text(item.tooltipTitle).indexOf(name) !== -1
}

function entryId(entry) {
  if (typeof entry === "string") return entry
  if (entry && typeof entry === "object") {
    var id = entry.id
    if (id !== undefined && id !== null && String(id) !== "") return String(id)
  }
  return ""
}

function layoutHasWidget(layout, id) {
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = layout && layout[sections[s]]
    if (!Array.isArray(entries)) continue
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === id) return true
    }
  }
  return false
}

// LocalSend's item shows no state, offers only Open and Quit, and its primary
// click is a no-op, so Share > Receive is the whole surface. Hiding it by hand
// doesn't stick either: LocalSend picks a fresh tray id every launch.
function ownedByRoseshell(item, layout) {
  return itemNamed(item, "localsend")
    || (layoutHasWidget(layout, "roseshell.dropbox") && itemNamed(item, "dropbox"))
}

// True when an icon is a single-tone glyph (white, grey or black) rather than
// full-colour artwork. `pixels` is RGBA bytes. A small coloured share still
// counts, so a glyph keeps its tint when it grows an unread badge.
function isMonochrome(pixels) {
  var opaque = 0
  var coloured = 0
  for (var i = 0; i + 3 < pixels.length; i += 4) {
    if (pixels[i + 3] < 64) continue
    opaque++
    var hi = Math.max(pixels[i], pixels[i + 1], pixels[i + 2])
    var lo = Math.min(pixels[i], pixels[i + 1], pixels[i + 2])
    if (hi - lo > 40) coloured++
  }
  return opaque > 0 && coloured <= opaque * 0.2
}

if (typeof module !== "undefined") {
  module.exports = {
    isMonochrome: isMonochrome,
    itemNamed: itemNamed,
    entryId: entryId,
    layoutHasWidget: layoutHasWidget,
    ownedByRoseshell: ownedByRoseshell
  }
}
