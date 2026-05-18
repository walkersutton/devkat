-- Archive final leaderboard snapshots for later use.
-- Weekly snapshots store the closed Monday→Monday top 10.
-- All-time snapshots store the top 5 cumulative totals as of each closed week.

create table if not exists public.leaderboard_history (
    leaderboard_type text not null check (leaderboard_type in ('all_time', 'weekly')),
    period_start date not null,
    period_end date not null,
    rank integer not null check (rank > 0),
    user_id uuid references auth.users on delete cascade not null,
    email text not null,
    total_tokens bigint not null check (total_tokens > 0),
    captured_at timestamptz not null default now(),
    primary key (leaderboard_type, period_start, rank),
    unique (leaderboard_type, period_start, user_id)
);

create index if not exists leaderboard_history_period_idx
    on public.leaderboard_history (leaderboard_type, period_start desc, rank asc);

create index if not exists sessions_started_at_idx
    on public.sessions (started_at desc);

create or replace function public.leaderboard_week_start_date(p_at timestamptz default now())
returns date
language sql
stable
set search_path = public, auth
as $$
    select date_trunc('week', p_at at time zone 'America/New_York')::date;
$$;

create or replace function public.backfill_leaderboard_history()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_first_week_start date;
    v_current_week_start date := public.leaderboard_week_start_date(now());
    v_last_completed_week_start date := v_current_week_start - 7;
begin
    select min(public.leaderboard_week_start_date(s.started_at))
    into v_first_week_start
    from public.sessions s;

    if v_first_week_start is null or v_last_completed_week_start < v_first_week_start then
        return;
    end if;

    -- If the most recent closed all-time snapshot exists, earlier weeks have
    -- already been backfilled by this function.
    if exists (
        select 1
        from public.leaderboard_history lh
        where lh.leaderboard_type = 'all_time'
          and lh.period_start = v_last_completed_week_start
    ) then
        return;
    end if;

    with weeks as (
        select gs::date as period_start
        from generate_series(
            v_first_week_start::timestamp,
            v_last_completed_week_start::timestamp,
            interval '7 days'
        ) as gs
    ),
    missing_periods as (
        select
            w.period_start,
            (w.period_start + 7)::date as period_end
        from weeks w
        where not exists (
            select 1
            from public.leaderboard_history lh
            where lh.leaderboard_type = 'weekly'
              and lh.period_start = w.period_start
        )
    ),
    weekly_totals as (
        select
            public.leaderboard_week_start_date(s.started_at) as period_start,
            s.user_id,
            au.email::text as email,
            sum(s.tokens)::bigint as total_tokens
        from public.sessions s
        join auth.users au on au.id = s.user_id
        where public.leaderboard_week_start_date(s.started_at) >= v_first_week_start
          and public.leaderboard_week_start_date(s.started_at) <= v_last_completed_week_start
        group by 1, 2, 3
        having sum(s.tokens) > 0
    ),
    ranked as (
        select
            'weekly'::text as leaderboard_type,
            mp.period_start,
            mp.period_end,
            wt.user_id,
            wt.email,
            wt.total_tokens,
            row_number() over (
                partition by mp.period_start
                order by wt.total_tokens desc, wt.email asc, wt.user_id asc
            ) as rank
        from missing_periods mp
        join weekly_totals wt on wt.period_start = mp.period_start
    )
    insert into public.leaderboard_history (
        leaderboard_type,
        period_start,
        period_end,
        rank,
        user_id,
        email,
        total_tokens
    )
    select
        leaderboard_type,
        period_start,
        period_end,
        rank,
        user_id,
        email,
        total_tokens
    from ranked
    where rank <= 10
    on conflict do nothing;

    with weeks as (
        select gs::date as period_start
        from generate_series(
            v_first_week_start::timestamp,
            v_last_completed_week_start::timestamp,
            interval '7 days'
        ) as gs
    ),
    missing_periods as (
        select
            w.period_start,
            (w.period_start + 7)::date as period_end
        from weeks w
        where not exists (
            select 1
            from public.leaderboard_history lh
            where lh.leaderboard_type = 'all_time'
              and lh.period_start = w.period_start
        )
    ),
    users as (
        select
            s.user_id,
            au.email::text as email,
            min(public.leaderboard_week_start_date(s.started_at)) as first_period_start
        from public.sessions s
        join auth.users au on au.id = s.user_id
        group by s.user_id, au.email
    ),
    weekly_totals as (
        select
            public.leaderboard_week_start_date(s.started_at) as period_start,
            s.user_id,
            sum(s.tokens)::bigint as weekly_tokens
        from public.sessions s
        where public.leaderboard_week_start_date(s.started_at) >= v_first_week_start
          and public.leaderboard_week_start_date(s.started_at) <= v_last_completed_week_start
        group by 1, 2
    ),
    user_week_grid as (
        select
            u.user_id,
            u.email,
            w.period_start,
            (w.period_start + 7)::date as period_end
        from users u
        join weeks w on w.period_start >= u.first_period_start
    ),
    cumulative_totals as (
        select
            uwg.period_start,
            uwg.period_end,
            uwg.user_id,
            uwg.email,
            sum(coalesce(wt.weekly_tokens, 0)) over (
                partition by uwg.user_id
                order by uwg.period_start
                rows between unbounded preceding and current row
            )::bigint as total_tokens
        from user_week_grid uwg
        left join weekly_totals wt
          on wt.user_id = uwg.user_id
         and wt.period_start = uwg.period_start
    ),
    ranked as (
        select
            'all_time'::text as leaderboard_type,
            ct.period_start,
            ct.period_end,
            ct.user_id,
            ct.email,
            ct.total_tokens,
            row_number() over (
                partition by ct.period_start
                order by ct.total_tokens desc, ct.email asc, ct.user_id asc
            ) as rank
        from cumulative_totals ct
        join missing_periods mp on mp.period_start = ct.period_start
        where ct.total_tokens > 0
    )
    insert into public.leaderboard_history (
        leaderboard_type,
        period_start,
        period_end,
        rank,
        user_id,
        email,
        total_tokens
    )
    select
        leaderboard_type,
        period_start,
        period_end,
        rank,
        user_id,
        email,
        total_tokens
    from ranked
    where rank <= 5
    on conflict do nothing;
end;
$$;

create or replace function public.token_leaderboard()
returns table(email text, total_tokens bigint)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    perform public.backfill_leaderboard_history();

    return query
    select
        au.email::text,
        coalesce(sum(s.tokens), 0)::bigint as total_tokens
    from auth.users au
    join public.sessions s on s.user_id = au.id
    group by au.email
    having coalesce(sum(s.tokens), 0) > 0
    order by total_tokens desc, au.email asc
    limit 5;
end;
$$;

create or replace function public.weekly_token_leaderboard()
returns table(email text, total_tokens bigint)
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
        coalesce(sum(s.tokens), 0)::bigint as total_tokens
    from auth.users au
    join public.sessions s on s.user_id = au.id
    where s.started_at >= v_current_week_start_ts
      and s.started_at < v_next_week_start_ts
    group by au.email
    having coalesce(sum(s.tokens), 0) > 0
    order by total_tokens desc, au.email asc
    limit 10;
end;
$$;

create or replace function public.leaderboard_history(
    p_leaderboard_type text,
    p_period_start date default null,
    p_limit integer default 12
)
returns table(
    period_start date,
    period_end date,
    rank integer,
    email text,
    total_tokens bigint
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
    if coalesce(p_leaderboard_type, '') not in ('all_time', 'weekly') then
        raise exception 'Invalid leaderboard_type: %', p_leaderboard_type;
    end if;

    perform public.backfill_leaderboard_history();

    return query
    with periods as (
        select distinct
            lh.period_start,
            lh.period_end
        from public.leaderboard_history lh
        where lh.leaderboard_type = p_leaderboard_type
          and (p_period_start is null or lh.period_start = p_period_start)
        order by lh.period_start desc
        limit case when p_period_start is null then greatest(coalesce(p_limit, 12), 1) else 1 end
    )
    select
        lh.period_start,
        lh.period_end,
        lh.rank,
        lh.email,
        lh.total_tokens
    from public.leaderboard_history lh
    join periods p
      on p.period_start = lh.period_start
     and p.period_end = lh.period_end
    where lh.leaderboard_type = p_leaderboard_type
    order by lh.period_start desc, lh.rank asc;
end;
$$;

revoke all on function public.leaderboard_week_start_date(timestamptz) from public;
revoke all on function public.backfill_leaderboard_history() from public;
revoke all on function public.token_leaderboard() from public;
revoke all on function public.weekly_token_leaderboard() from public;
revoke all on function public.leaderboard_history(text, date, integer) from public;

grant execute on function public.token_leaderboard() to authenticated;
grant execute on function public.weekly_token_leaderboard() to authenticated;
grant execute on function public.leaderboard_history(text, date, integer) to authenticated;
