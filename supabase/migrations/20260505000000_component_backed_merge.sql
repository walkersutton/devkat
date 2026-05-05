-- Make session merging idempotent.
--
-- The previous aggregate-only merge could not distinguish "new source to add"
-- from "same source re-pushed with fresher totals", so active sessions were
-- added to themselves every sync cycle. Store replaceable per-source
-- components, then recompute the public sessions row from those components.

create table if not exists session_components (
    user_id           uuid        not null,
    session_id        text        not null,
    source            text        not null,
    source_session_id text        not null,
    started_at        timestamptz not null,
    ended_at          timestamptz not null,
    active_duration   float8      not null,
    lines_added       int         not null,
    lines_removed     int         not null,
    files_touched     int         not null,
    tokens            int         not null,
    model             text        not null default '',
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    primary key (user_id, session_id, source, source_session_id)
);

alter table session_components enable row level security;

drop policy if exists "Users can read own session components" on session_components;
create policy "Users can read own session components"
    on session_components for select
    using (auth.uid() = user_id);

drop policy if exists "Users can write own session components" on session_components;
create policy "Users can write own session components"
    on session_components for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

create index if not exists session_components_lookup
    on session_components (user_id, source, source_session_id);

create index if not exists session_components_time
    on session_components (user_id, session_id, started_at, ended_at);

insert into session_components (
    user_id, session_id, source, source_session_id,
    started_at, ended_at, active_duration,
    lines_added, lines_removed, files_touched, tokens, model
)
select
    user_id,
    id,
    coalesce(sources[1], 'unknown'),
    id,
    started_at,
    ended_at,
    active_duration,
    lines_added,
    lines_removed,
    files_touched,
    tokens,
    coalesce(models[1], '')
from sessions
on conflict (user_id, session_id, source, source_session_id) do nothing;

create or replace function merge_session(
    p_id              text,
    p_started_at      timestamptz,
    p_ended_at        timestamptz,
    p_active_duration float8,
    p_lines_added     int,
    p_lines_removed   int,
    p_files_touched   int,
    p_tokens          int,
    p_model           text,
    p_repo_alias      text,
    p_git_branch      text,
    p_source          text
) returns text
language plpgsql security definer
as $$
declare
    v_uid       uuid := auth.uid();
    v_target_id text;
    v_gap       interval := interval '30 minutes';
begin
    if v_uid is null then
        raise exception 'merge_session requires an authenticated user';
    end if;

    -- Exact source-session match: this is a re-push, so replace its component.
    select session_id into v_target_id
    from session_components
    where user_id = v_uid
      and source = p_source
      and source_session_id = p_id
    limit 1;

    -- Exact aggregate row match, useful before a component exists.
    if v_target_id is null then
        select id into v_target_id
        from sessions
        where user_id = v_uid
          and id = p_id
        limit 1;
    end if;

    -- Otherwise merge into the closest overlapping/nearby aggregate row.
    if v_target_id is null then
        select id into v_target_id
        from sessions
        where user_id = v_uid
          and started_at <= p_ended_at + v_gap
          and ended_at   >= p_started_at - v_gap
        order by
            case when started_at <= p_started_at and ended_at >= p_ended_at then 0 else 1 end,
            greatest(0, extract(epoch from (p_started_at - ended_at)),
                        extract(epoch from (started_at - p_ended_at)))
        limit 1;
    end if;

    if v_target_id is null then
        v_target_id := p_id;

        insert into sessions (
            id, user_id, started_at, ended_at, active_duration,
            lines_added, lines_removed, files_touched, tokens,
            sources, models, repo_alias, git_branch
        )
        values (
            v_target_id, v_uid, p_started_at, p_ended_at, p_active_duration,
            p_lines_added, p_lines_removed, p_files_touched, p_tokens,
            array[p_source], array[p_model], p_repo_alias, p_git_branch
        )
        on conflict (id) do nothing;
    end if;

    -- Remove stale same-source components for the same target/range. This
    -- cleans rows created before component-backed merging existed.
    delete from session_components
    where user_id = v_uid
      and session_id = v_target_id
      and source = p_source
      and source_session_id <> p_id
      and started_at <= p_ended_at + v_gap
      and ended_at   >= p_started_at - v_gap;

    insert into session_components (
        user_id, session_id, source, source_session_id,
        started_at, ended_at, active_duration,
        lines_added, lines_removed, files_touched, tokens, model
    )
    values (
        v_uid, v_target_id, p_source, p_id,
        p_started_at, p_ended_at, p_active_duration,
        p_lines_added, p_lines_removed, p_files_touched, p_tokens,
        coalesce(p_model, '')
    )
    on conflict (user_id, session_id, source, source_session_id) do update set
        started_at      = excluded.started_at,
        ended_at        = excluded.ended_at,
        active_duration = excluded.active_duration,
        lines_added     = excluded.lines_added,
        lines_removed   = excluded.lines_removed,
        files_touched   = excluded.files_touched,
        tokens          = excluded.tokens,
        model           = excluded.model,
        updated_at      = now();

    with agg as (
        select
            min(started_at) as started_at,
            max(ended_at) as ended_at,
            sum(active_duration) as active_duration,
            sum(lines_added)::int as lines_added,
            sum(lines_removed)::int as lines_removed,
            max(files_touched)::int as files_touched,
            sum(tokens)::int as tokens,
            array_agg(distinct source order by source) as sources,
            coalesce(
                array_agg(distinct model order by model) filter (where model <> ''),
                '{}'::text[]
            ) as models
        from session_components
        where user_id = v_uid
          and session_id = v_target_id
    )
    update sessions set
        started_at      = agg.started_at,
        ended_at        = agg.ended_at,
        active_duration = agg.active_duration,
        lines_added     = agg.lines_added,
        lines_removed   = agg.lines_removed,
        files_touched   = agg.files_touched,
        tokens          = agg.tokens,
        sources         = agg.sources,
        models          = agg.models,
        repo_alias      = coalesce(sessions.repo_alias, p_repo_alias),
        git_branch      = coalesce(p_git_branch, sessions.git_branch)
    from agg
    where sessions.user_id = v_uid
      and sessions.id = v_target_id;

    return v_target_id;
end;
$$;
