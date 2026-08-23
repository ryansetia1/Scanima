"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/browser";

export type RealtimeWatch = {
  table: string;
  /** Postgres Changes filter string, e.g. "id=eq.<uuid>". Omit to watch every row. */
  filter?: string;
};

/**
 * Subscribes to postgres_changes on the given tables and calls
 * router.refresh() on any matching event. The realtime payload itself is
 * never used directly for rendering -- this is purely a "something
 * changed, refetch through the normal staff-gated admin_moderation path"
 * signal, so that Edge Function stays the single source of render logic.
 *
 * Requires the staff-scoped RLS SELECT policies from
 * 20260823160255_atlas_moderation_realtime_rls.sql -- without them,
 * postgres_changes delivers nothing (Realtime respects RLS the same way
 * REST does).
 */
export function RealtimeRefresh({ watches }: { watches: RealtimeWatch[] }) {
  const router = useRouter();
  const key = watches.map((w) => `${w.table}:${w.filter ?? ""}`).join(",");

  useEffect(() => {
    const supabase = createClient();
    const channel = supabase.channel(`admin-refresh-${key}`);
    for (const watch of watches) {
      channel.on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: watch.table,
          ...(watch.filter ? { filter: watch.filter } : {}),
        },
        () => router.refresh(),
      );
    }
    channel.subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
    // `watches` is intentionally summarized into `key` above so this effect
    // only re-subscribes when the actual watch set changes, not on every
    // render (the caller usually passes a fresh array literal each time).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  return null;
}
