export function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function renderMapPreview(map) {
  const nodes = Array.isArray(map?.nodes) ? map.nodes : [];
  const byDepth = new Map();
  for (const node of nodes) {
    const depth = Number(node.depth) || 0;
    if (!byDepth.has(depth)) byDepth.set(depth, []);
    byDepth.get(depth).push(node);
  }
  const depths = [...byDepth.keys()].sort((a, b) => a - b);
  const rows = depths.map((depth) => {
    const cells = byDepth.get(depth).map((node) =>
      `<span title="${escapeHtml(node.id)}">${escapeHtml(node.kind)}${node.opponent_id ? ` (${escapeHtml(node.opponent_id)})` : ""}</span>`,
    ).join(" · ");
    return `<div><strong>Depth ${depth}:</strong> ${cells}</div>`;
  }).join("");
  return `<div class="muted">seed <code>${escapeHtml(map.seed ?? "")}</code></div>${rows}`;
}
