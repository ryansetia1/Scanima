import type { CaseCategory } from "./types";

/** Left-border color for a queue row, structural (age), not decorative. */
export function ageBorderColor(createdAt: string): string {
  const ageHours = (Date.now() - new Date(createdAt).getTime()) / 3_600_000;
  if (ageHours >= 48) return "border-l-deck-danger";
  if (ageHours >= 24) return "border-l-deck-gold";
  return "border-l-deck-border";
}

export function categoryLabel(category: CaseCategory): string {
  switch (category) {
    case "sexual":
      return "Sexual";
    case "gore":
      return "Gore";
    case "hate":
      return "Hate";
    case "ip_character":
      return "IP character";
    default:
      return "Uncategorized";
  }
}

export function categoryTextColor(category: CaseCategory): string {
  switch (category) {
    case "sexual":
    case "gore":
    case "hate":
      return "text-deck-danger";
    case "ip_character":
      return "text-deck-secondary";
    default:
      return "text-deck-muted";
  }
}

export function formatRelativeAge(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime();
  const minutes = Math.floor(ms / 60_000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

export function formatDateTime(iso: string): string {
  return new Date(iso).toLocaleString(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  });
}

export function formatSeconds(seconds: number | null): string {
  if (seconds === null) return "—";
  if (seconds < 60) return `${Math.round(seconds)}s`;
  const minutes = seconds / 60;
  if (minutes < 60) return `${minutes.toFixed(1)}m`;
  const hours = minutes / 60;
  if (hours < 24) return `${hours.toFixed(1)}h`;
  return `${(hours / 24).toFixed(1)}d`;
}
