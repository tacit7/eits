// Score an item against a query. Higher = better match.
// 3: exact match on slug
// 2: slug starts with query
// 1: slug contains query
// 0: description/type contains query
// -1: no match
function scoreItem(item, q, activeFlags) {
  if (!q) {
    let score = 1
    if (item.type === 'flag' && activeFlags && activeFlags[item.slug] !== undefined) {
      score += 10
    }
    return score
  }
  const slug = item.slug.toLowerCase()
  const desc = (item.description || '').toLowerCase()
  const type = (item.type || '').toLowerCase()
  let score = -1
  if (slug === q) score = 3
  else if (slug.startsWith(q)) score = 2
  else if (slug.includes(q)) score = 1
  else if (desc.includes(q) || type.includes(q)) score = 0

  if (score >= 0 && item.type === 'flag' && activeFlags && activeFlags[item.slug] !== undefined) {
    score += 10
  }
  return score
}

// Filter items by typeFilter and query, score and sort them.
// Returns up to MAX_RESULTS items ordered best-match first.
export function filterAndScore(items, query, typeFilter, activeFlags) {
  const MAX_RESULTS = 8
  const q = (query || '').toLowerCase()

  const pool = typeFilter
    ? items.filter(item => item.type === typeFilter)
    : items.filter(item => item.type !== 'agent')

  const scored = pool
    .map(item => ({ item, score: scoreItem(item, q, activeFlags) }))
    .filter(({ score }) => score >= 0)

  scored.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score
    return a.item.slug.localeCompare(b.item.slug)
  })

  return scored.slice(0, MAX_RESULTS).map(({ item }) => item)
}
