export function _generateHintLabels(count: number): string[] {
  const alpha = "abcdefghijklmnopqrstuvwxyz"
  const labels: string[] = []
  for (let i = 0; labels.length < count && i < alpha.length; i++) {
    labels.push(alpha[i])
  }
  for (let i = 0; labels.length < count && i < alpha.length; i++) {
    for (let j = 0; labels.length < count && j < alpha.length; j++) {
      labels.push(alpha[i] + alpha[j])
    }
  }
  return labels
}
