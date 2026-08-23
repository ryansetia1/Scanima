export function PageLoading() {
  return (
    <div className="flex items-center gap-3 p-6 text-sm text-deck-muted">
      <span className="h-5 w-5 animate-spin rounded-full border-2 border-deck-border border-t-deck-secondary" />
      Loading…
    </div>
  );
}
