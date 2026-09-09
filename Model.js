function contains(values, code) {
  return (values || []).indexOf(String(code || "").toUpperCase()) >= 0
}

function decorate(prices, pins) {
  return (prices || []).map(function(item) {
    var copy = {}
    for (var key in item) copy[key] = item[key]
    copy.pinned = contains(pins, item.code)
    return copy
  })
}

function sortedRows(prices, pins) {
  return decorate(prices, pins)
}

function compactPrice(value) {
  var n = Number(value)
  if (!isFinite(n)) return "—"
  if (Math.abs(n) >= 1000000) return (n / 1000000).toFixed(n >= 10000000 ? 1 : 2).replace(/\.0$/, "") + "m"
  if (Math.abs(n) >= 1000) return (n / 1000).toFixed(n >= 100000 ? 1 : 2).replace(/\.0$/, "") + "k"
  return String(n)
}

function directionGlyph(direction) {
  if (direction === "up") return "↗"
  if (direction === "down") return "↘"
  return "•"
}

function pinnedRows(prices, pins, maximum) {
  var byCode = {}
  ;(prices || []).forEach(function(item) { byCode[item.code] = item })
  var rows = []
  ;(pins || []).forEach(function(code) {
    if (byCode[code] && rows.length < maximum) rows.push(byCode[code])
  })
  return rows
}

function barLabel(prices, pins, maximum, vertical) {
  var rows = pinnedRows(prices, pins, maximum)
  if (vertical || !rows.length) return "$"
  return "$  " + rows.map(function(item) {
    return item.code + " " + compactPrice(item.sell)
  }).join("   ")
}

function formatPrice(value) {
  var n = Number(value)
  if (!isFinite(n)) return "—"
  return Math.round(n).toLocaleString(Qt.locale("en_US"), "f", 0)
}

function freshness(stale) {
  if (stale) return "Cached prices · connection unavailable"
  return "Live market prices"
}

function localUpdateTime(value) {
  var timestamp = new Date(String(value || ""))
  if (isNaN(timestamp.getTime())) return ""
  return "Last updated " + timestamp.toLocaleString(
    Qt.locale("en_US"), "MMM d, yyyy · HH:mm")
}
