-- Delete sessions whose entire timespan predates the owning user's account.
-- A session is considered "pre-account" if it ended at or before the user
-- was created. Sessions that started before but extend past account creation
-- (i.e. live sessions captured at install time) are preserved.
--
-- This is a one-shot cleanup. Re-running is a no-op once the CLI is updated
-- to apply the same per-user cutoff client-side.

delete from sessions s
using auth.users u
where s.user_id = u.id
  and s.ended_at <= u.created_at;
