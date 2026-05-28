-- Weekly top-10 token leaderboard. Counts sessions that started during the
-- current America/New_York week, where the week resets every Monday at 12:00 AM.

create or replace function weekly_token_leaderboard()
returns table(email text, total_tokens bigint)
language sql
security definer
set search_path = public, auth
as $$
    with week_window as (
        select
            (
                date_trunc('week', now() at time zone 'America/New_York')
                at time zone 'America/New_York'
            ) as week_start
    )
    select
        au.email::text,
        coalesce(sum(s.tokens), 0)::bigint as total_tokens
    from auth.users au
    join public.sessions s on s.user_id = au.id
    cross join week_window ww
    where s.started_at >= ww.week_start
      and s.started_at < ww.week_start + interval '7 days'
    group by au.email
    having coalesce(sum(s.tokens), 0) > 0
    order by total_tokens desc
    limit 10;
$$;

revoke all on function weekly_token_leaderboard() from public;
grant execute on function weekly_token_leaderboard() to authenticated;
