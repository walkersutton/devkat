-- Expand leaderboard RPCs for the authenticated leaderboard tab.
-- Existing callers can keep reading email + total_tokens; the extra columns
-- power denser rank-table stats in the web app.

drop function if exists public.token_leaderboard();
drop function if exists public.weekly_token_leaderboard();

create or replace function public.token_leaderboard()
returns table(
    email text,
    total_tokens bigint,
    total_lines bigint,
    total_sessions bigint,
    active_seconds double precision
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    perform public.backfill_leaderboard_history();

    return query
    select
        au.email::text,
        coalesce(sum(s.tokens), 0)::bigint as total_tokens,
        coalesce(sum(s.lines_added + s.lines_removed), 0)::bigint as total_lines,
        count(s.id)::bigint as total_sessions,
        coalesce(sum(s.active_duration), 0)::double precision as active_seconds
    from auth.users au
    join public.sessions s on s.user_id = au.id
    group by au.email
    having coalesce(sum(s.tokens), 0) > 0
    order by total_tokens desc, au.email asc
    limit 25;
end;
$$;

create or replace function public.weekly_token_leaderboard()
returns table(
    email text,
    total_tokens bigint,
    total_lines bigint,
    total_sessions bigint,
    active_seconds double precision
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_current_week_start date := public.leaderboard_week_start_date(now());
    v_current_week_start_ts timestamptz := (v_current_week_start::timestamp at time zone 'America/New_York');
    v_next_week_start_ts timestamptz := ((v_current_week_start + 7)::timestamp at time zone 'America/New_York');
begin
    perform public.backfill_leaderboard_history();

    return query
    select
        au.email::text,
        coalesce(sum(s.tokens), 0)::bigint as total_tokens,
        coalesce(sum(s.lines_added + s.lines_removed), 0)::bigint as total_lines,
        count(s.id)::bigint as total_sessions,
        coalesce(sum(s.active_duration), 0)::double precision as active_seconds
    from auth.users au
    join public.sessions s on s.user_id = au.id
    where s.started_at >= v_current_week_start_ts
      and s.started_at < v_next_week_start_ts
    group by au.email
    having coalesce(sum(s.tokens), 0) > 0
    order by total_tokens desc, au.email asc
    limit 25;
end;
$$;

create or replace function public.last_24h_token_leaderboard()
returns table(
    email text,
    total_tokens bigint,
    total_lines bigint,
    total_sessions bigint,
    active_seconds double precision
)
language sql
security definer
set search_path = public, auth
as $$
    select
        au.email::text,
        coalesce(sum(s.tokens), 0)::bigint as total_tokens,
        coalesce(sum(s.lines_added + s.lines_removed), 0)::bigint as total_lines,
        count(s.id)::bigint as total_sessions,
        coalesce(sum(s.active_duration), 0)::double precision as active_seconds
    from auth.users au
    join public.sessions s on s.user_id = au.id
    where s.started_at >= now() - interval '24 hours'
    group by au.email
    having coalesce(sum(s.tokens), 0) > 0
    order by total_tokens desc, au.email asc
    limit 25;
$$;

create or replace function public.source_token_leaderboard(p_window text default 'weekly')
returns table(
    source text,
    email text,
    total_tokens bigint,
    total_sessions bigint,
    active_seconds double precision
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if coalesce(p_window, '') not in ('24h', 'weekly', 'all_time') then
        raise exception 'Invalid leaderboard window: %', p_window;
    end if;

    return query
    with filtered_components as (
        select sc.*
        from public.session_components sc
        where
            case p_window
                when '24h' then sc.started_at >= now() - interval '24 hours'
                when 'weekly' then sc.started_at >= (
                    public.leaderboard_week_start_date(now())::timestamp at time zone 'America/New_York'
                )
                    and sc.started_at < (
                        (public.leaderboard_week_start_date(now()) + 7)::timestamp at time zone 'America/New_York'
                    )
                else true
            end
    ),
    ranked as (
        select
            fc.source,
            au.email::text as email,
            coalesce(sum(fc.tokens), 0)::bigint as total_tokens,
            count(fc.source_session_id)::bigint as total_sessions,
            coalesce(sum(fc.active_duration), 0)::double precision as active_seconds,
            row_number() over (
                partition by fc.source
                order by coalesce(sum(fc.tokens), 0) desc, au.email asc
            ) as source_rank
        from filtered_components fc
        join auth.users au on au.id = fc.user_id
        group by fc.source, au.email
        having coalesce(sum(fc.tokens), 0) > 0
    )
    select
        ranked.source,
        ranked.email,
        ranked.total_tokens,
        ranked.total_sessions,
        ranked.active_seconds
    from ranked
    where ranked.source_rank = 1
    order by ranked.total_tokens desc, ranked.source asc;
end;
$$;

revoke all on function public.token_leaderboard() from public;
revoke all on function public.weekly_token_leaderboard() from public;
revoke all on function public.last_24h_token_leaderboard() from public;
revoke all on function public.source_token_leaderboard(text) from public;

grant execute on function public.token_leaderboard() to authenticated;
grant execute on function public.weekly_token_leaderboard() to authenticated;
grant execute on function public.last_24h_token_leaderboard() to authenticated;
grant execute on function public.source_token_leaderboard(text) to authenticated;
