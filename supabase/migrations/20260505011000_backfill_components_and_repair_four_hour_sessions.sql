-- Backfill any aggregate sessions that do not yet have source components,
-- then rerun the 4-hour consolidation. This handles rows created before a
-- component existed for every visible session.

insert into session_components (
    user_id, session_id, source, source_session_id,
    started_at, ended_at, active_duration,
    lines_added, lines_removed, files_touched, tokens, model
)
select
    s.user_id,
    s.id,
    coalesce(s.sources[1], 'unknown'),
    s.id,
    s.started_at,
    s.ended_at,
    s.active_duration,
    s.lines_added,
    s.lines_removed,
    s.files_touched,
    s.tokens,
    coalesce(s.models[1], '')
from sessions s
where not exists (
    select 1
    from session_components sc
    where sc.user_id = s.user_id
      and sc.session_id = s.id
      and sc.source_session_id = s.id
)
on conflict (user_id, session_id, source, source_session_id) do update set
    started_at = excluded.started_at,
    ended_at = excluded.ended_at,
    active_duration = excluded.active_duration,
    lines_added = excluded.lines_added,
    lines_removed = excluded.lines_removed,
    files_touched = excluded.files_touched,
    tokens = excluded.tokens,
    model = excluded.model,
    updated_at = now();

with ordered_components as (
    select
        sc.*,
        coalesce(s.repo_alias, '') as repo_alias,
        coalesce(s.git_branch, '') as git_branch,
        max(sc.ended_at) over (
            partition by sc.user_id, coalesce(s.repo_alias, ''), coalesce(s.git_branch, '')
            order by sc.started_at, sc.ended_at, sc.session_id, sc.source, sc.source_session_id
            rows between unbounded preceding and 1 preceding
        ) as previous_ended_at
    from session_components sc
    left join sessions s
      on s.user_id = sc.user_id
     and s.id = sc.session_id
),
grouped_components as (
    select
        *,
        sum(
            case
                when previous_ended_at is null or started_at > previous_ended_at + interval '4 hours' then 1
                else 0
            end
        ) over (
            partition by user_id, repo_alias, git_branch
            order by started_at, ended_at, session_id, source, source_session_id
        ) as session_group
    from ordered_components
),
canonical_groups as (
    select
        user_id,
        repo_alias,
        git_branch,
        session_group,
        (array_agg(session_id order by started_at, ended_at, session_id))[1] as canonical_session_id
    from grouped_components
    group by user_id, repo_alias, git_branch, session_group
),
remapped_components as (
    update session_components sc
    set session_id = cg.canonical_session_id,
        updated_at = now()
    from grouped_components gc
    join canonical_groups cg
      on cg.user_id = gc.user_id
     and cg.repo_alias = gc.repo_alias
     and cg.git_branch = gc.git_branch
     and cg.session_group = gc.session_group
    where sc.user_id = gc.user_id
      and sc.session_id = gc.session_id
      and sc.source = gc.source
      and sc.source_session_id = gc.source_session_id
      and sc.session_id <> cg.canonical_session_id
    returning sc.user_id
),
affected_users as (
    select user_id from remapped_components
    union
    select distinct user_id from session_components
),
session_aggregates as (
    select
        sc.user_id,
        sc.session_id,
        min(sc.started_at) as started_at,
        max(sc.ended_at) as ended_at,
        sum(sc.active_duration) as active_duration,
        sum(sc.lines_added)::int as lines_added,
        sum(sc.lines_removed)::int as lines_removed,
        max(sc.files_touched)::int as files_touched,
        sum(sc.tokens)::int as tokens,
        array_agg(distinct sc.source order by sc.source) as sources,
        coalesce(
            array_agg(distinct sc.model order by sc.model) filter (where sc.model <> ''),
            '{}'::text[]
        ) as models
    from session_components sc
    join affected_users au on au.user_id = sc.user_id
    group by sc.user_id, sc.session_id
),
updated_sessions as (
    update sessions s
    set started_at = sa.started_at,
        ended_at = sa.ended_at,
        active_duration = sa.active_duration,
        lines_added = sa.lines_added,
        lines_removed = sa.lines_removed,
        files_touched = sa.files_touched,
        tokens = sa.tokens,
        sources = sa.sources,
        models = sa.models
    from session_aggregates sa
    where s.user_id = sa.user_id
      and s.id = sa.session_id
    returning s.user_id, s.id
)
delete from sessions s
where exists (
    select 1 from affected_users au where au.user_id = s.user_id
)
and not exists (
    select 1
    from session_components sc
    where sc.user_id = s.user_id
      and sc.session_id = s.id
);
