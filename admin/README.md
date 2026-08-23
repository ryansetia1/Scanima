# Scanima Control Deck

Staff-only moderation console for the Scanima Atlas gallery. Next.js 16 App
Router, TypeScript, Tailwind v4. Design contract:
[`docs/designs/2026-08-23-atlas-moderation-admin.md`](../docs/designs/2026-08-23-atlas-moderation-admin.md)
and [`.cursor/rules/admin-guardrails.mdc`](../.cursor/rules/admin-guardrails.mdc).

## What this is

A thin browser client over one privileged Edge Function,
`admin_moderation`. This app never holds a service-role key and never
queries Postgres directly — every read and write goes through that function,
which re-verifies the caller's staff role from `staff_accounts` on every
call. `proxy.ts` only refreshes the Supabase session cookie and redirects
optimistically to `/login`; it is not the authorization boundary. The real
gate is the `whoami` call in `app/(protected)/layout.tsx`.

## Setup

```bash
npm install
cp .env.local.example .env.local
# fill in NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY
npm run dev
```

## Manual steps outside this scaffold's scope

These need a real Supabase project and were **not** done as part of building
this app:

1. Set real values in `.env.local` (Supabase project URL + publishable/anon
   key — never the service-role key).
2. Add `http://localhost:3000/auth/callback` (and your deployed origin's
   equivalent) to the Supabase Auth redirect allowlist, without touching the
   game client's `scanima://auth/callback` entry.
3. Deploy the backend function this app calls:
   `supabase functions deploy admin_moderation`.
4. Grant yourself a `staff_accounts` row with role `admin` — bootstrapping
   the first admin is manual SQL, by design (see the design doc's role
   matrix).

## Checks

```bash
npx tsc --noEmit
npm run lint
npm run build
```
