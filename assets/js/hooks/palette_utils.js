export function fuzzyPositions(label, q) {
  const lc = label.toLowerCase()
  const positions = []
  let qi = 0
  for (let i = 0; i < lc.length && qi < q.length; i++) {
    if (lc[i] === q[qi]) { positions.push(i); qi++ }
  }
  return qi === q.length ? positions : null
}

export function scoreCmd(cmd, q, positions) {
  const label = cmd.label.toLowerCase()
  let score = 0

  if (label === q) score += 200
  if (label.startsWith(q)) score += 100
  if (label.includes(q)) score += 50

  if (positions !== null) {
    score += 60
    let consecutive = 0
    for (let i = 1; i < positions.length; i++) {
      if (positions[i] === positions[i - 1] + 1) consecutive++
    }
    score += consecutive * 2
  }

  const kws = (cmd.keywords || []).join(" ").toLowerCase()
  if (kws && kws.includes(q)) score += 30
  if (cmd.hint && cmd.hint.toLowerCase().includes(q)) score += 15
  if (cmd.group && cmd.group.toLowerCase().includes(q)) score += 10

  return score
}

export function escapeHtml(value) {
  return String(value || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;")
}

export function highlightLabel(label, matchedPositions) {
  return [...label].map((char, i) =>
    matchedPositions.has(i)
      ? `<mark class="bg-transparent text-primary font-semibold">${escapeHtml(char)}</mark>`
      : escapeHtml(char)
  ).join("")
}
