-- Recover from over-merge introduced by 20260511204333.
--
-- That migration's "fold any aggregate whose window overlaps within 4h" loop
-- transitively pulled in unrelated aggregates whenever a long-running session
-- spanned the gaps between them. Result: every user's components collapsed
-- onto a single sessions row.
--
-- The correct grouping rule (matching what the on-disk JSONL parser does) is:
-- sort a user's session_components by started_at and start a new session
-- wherever the gap to the running max(ended_at) exceeds 4 hours. No window
-- overlap, no transitivity.
--
-- This migration:
--   1. Replaces merge_session with a version that, after upserting the new
--      component, re-derives every chain for the user from session_components
--      using the 4h-gap rule and rebuilds the sessions table to match.
--   2. Runs the same re-fragmentation for every user as a one-shot recovery.
--
-- Notes on metadata recovery: session_components does not carry repo_alias /
-- git_branch, so newly created sessions rows start with NULL there. The next
-- daemon push for any source_session_id in the chain fills them via the
-- coalesce-on-update at the end of merge_session.

create or replace function devkat_refragment_user(p_uid uuid, p_seed_chain_id text default null)
returns text
language plpgsql
as $$
declare
    v_seed_chain_id text;
begin
    -- Compute chains, pick canonical id per chain, re-parent components.
    with ordered as (
        select sc.*,
            max(ended_at) over (
                partition by user_id
                order by started_at, ended_at, source, source_session_id
                rows between unbounded preceding and 1 preceding
            ) as prev_max_ended
        from session_components sc
        where user_id = p_uid
    ),
    chained as (
        select *,
            sum(case when prev_max_ended is null
                          or started_at > prev_max_ended + interval '4 hours'
                     then 1 else 0 end)
                over (partition by user_id
                      order by started_at, ended_at, source, source_session_id) as chain
        from ordered
    ),
    canonical as (
        select user_id, chain,
            (array_agg(source_session_id
                       order by started_at, ended_at, source, source_session_id))[1] as canonical_id
        from chained
        group by user_id, chain
    ),
    moved as (
        update session_components sc
        set session_id = c.canonical_id,
            updated_at = now()
        from chained ch
        join canonical c on c.user_id = ch.user_id and c.chain = ch.chain
        where sc.user_id = ch.user_id
          and sc.source = ch.source
          and sc.source_session_id = ch.source_session_id
          and sc.session_id <> c.canonical_id
        returning sc.user_id
    ),
    -- Upsert one row per chain.
    chain_agg as (
        select
            c.canonical_id,
            ch.user_id,
            min(ch.started_at) as started_at,
            max(ch.ended_at) as ended_at,
            sum(ch.active_duration) as active_duration,
            sum(ch.lines_added)::int as lines_added,
            sum(ch.lines_removed)::int as lines_removed,
            max(ch.files_touched)::int as files_touched,
            sum(ch.tokens)::int as tokens,
            array_agg(distinct ch.source order by ch.source) as sources,
            coalesce(
                array_agg(distinct ch.model order by ch.model) filter (where ch.model <> ''),
                '{}'::text[]
            ) as models
        from chained ch
        join canonical c on c.user_id = ch.user_id and c.chain = ch.chain
        group by c.canonical_id, ch.user_id
    ),
    -- For seed lookup: which chain holds p_seed_chain_id (if it was a source_session_id)?
    seeded as (
        select c.canonical_id
        from chained ch
        join canonical c on c.user_id = ch.user_id and c.chain = ch.chain
        where p_seed_chain_id is not null
          and ch.source_session_id = p_seed_chain_id
        limit 1
    ),
    upserted as (
        insert into sessions (
            id, user_id, started_at, ended_at, active_duration,
            lines_added, lines_removed, files_touched, tokens,
            sources, models
        )
        select
            canonical_id, user_id, started_at, ended_at, active_duration,
            lines_added, lines_removed, files_touched, tokens,
            sources, models
        from chain_agg
        on conflict (id) do update set
            started_at      = excluded.started_at,
            ended_at        = excluded.ended_at,
            active_duration = excluded.active_duration,
            lines_added     = excluded.lines_added,
            lines_removed   = excluded.lines_removed,
            files_touched   = excluded.files_touched,
            tokens          = excluded.tokens,
            sources         = excluded.sources,
            models          = excluded.models
        returning 1
    )
    select canonical_id into v_seed_chain_id from seeded;

    -- Sweep any sessions row that no longer has components.
    delete from sessions s
    where s.user_id = p_uid
      and not exists (
          select 1 from session_components sc
          where sc.user_id = s.user_id and sc.session_id = s.id
      );

    return v_seed_chain_id;
end;
$$;

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
begin
    if v_uid is null then
        raise exception 'merge_session requires an authenticated user';
    end if;

    -- Component lives wherever its current row points; if it doesn't exist
    -- yet, seed it under its own source_session_id and let refragment move it.
    select session_id into v_target_id
    from session_components
    where user_id = v_uid
      and source = p_source
      and source_session_id = p_id
    limit 1;

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
            array[p_source], array[coalesce(p_model, '')],
            p_repo_alias, p_git_branch
        )
        on conflict (id) do nothing;
    end if;

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

    -- Re-derive chains for the whole user. Returns the canonical id holding
    -- the just-pushed source_session_id.
    v_target_id := devkat_refragment_user(v_uid, p_id);

    -- Backfill repo / branch on the canonical row if missing.
    update sessions set
        repo_alias = coalesce(repo_alias, p_repo_alias),
        git_branch = coalesce(git_branch, p_git_branch)
    where user_id = v_uid
      and id = v_target_id;

    return v_target_id;
end;
$$;

-- One-shot recovery: re-fragment every user's components.
do $$
declare
    r_user uuid;
begin
    for r_user in select distinct user_id from session_components loop
        perform devkat_refragment_user(r_user, null);
    end loop;
end $$;
