-- battle_daily_reward_status() memeriksa apakah session tertentu adalah win
-- berhadiah atau Practice. Indeks ini membuat lookup itu konstan sekaligus
-- menegakkan satu ledger reward maksimal per battle session.
create unique index quota_ledger_battle_win_session_unique
  on public.quota_ledger (ref_id)
  where reason = 'battle_win' and ref_id is not null;
