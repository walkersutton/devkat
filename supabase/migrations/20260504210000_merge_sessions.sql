-- Drop the view approach — we want actual merged rows instead
drop view if exists unified_sessions;

-- Convert source (single text) → sources (array of tools used)
alter table sessions drop constraint if exists sessions_source_check;
alter table sessions rename column source to _source_old;
alter table sessions add column sources text[] not null default '{claude}';

-- Backfill from old column
update sessions set sources = array[_source_old];
alter table sessions drop column _source_old;

-- Add models array (a merged session may use claude-4-opus + gpt-5)
alter table sessions add column models text[] not null default '{}';

-- Backfill models from the existing model column
update sessions set models = array[model] where model != '';

-- Drop the old scalar model column — models[] replaces it
-- Keep pace generated column working by not touching active_duration/lines
alter table sessions drop column if exists pace;
alter table sessions drop column model;

-- Re-add pace as generated column
alter table sessions
    add column pace int generated always as (
        case
            when active_duration > 0
            then floor(
                (lines_added + lines_removed)::double precision
                / (active_duration / 3600.0)
            )::int
            else 0
        end
    ) stored;

-- Drop old indexes
drop index if exists sessions_user_source;

-- Upsert function: merges into an existing overlapping session if one exists
-- "Overlapping" = same user, time ranges within 30 minutes of each other
create or replace function merge_session(
    p_id            text,
    p_started_at    timestamptz,
    p_ended_at      timestamptz,
    p_active_duration float8,
    p_lines_added   int,
    p_lines_removed int,
    p_files_touched int,
    p_tokens        int,
    p_model         text,
    p_repo_alias    text,
    p_git_branch    text,
    p_source        text
) returns text
language plpgsql security definer
as $$
declare
    v_uid       uuid := auth.uid();
    v_existing  record;
    v_gap       interval := interval '30 minutes';
begin
    -- Find an existing session that overlaps or is within 30 min
    select * into v_existing
    from sessions
    where user_id = v_uid
      and started_at <= p_ended_at + v_gap
      and ended_at   >= p_started_at - v_gap
    order by started_at asc
    limit 1;

    if found then
        -- Merge into existing row
        update sessions set
            started_at      = least(sessions.started_at, p_started_at),
            ended_at        = greatest(sessions.ended_at, p_ended_at),
            active_duration = sessions.active_duration + p_active_duration,
            lines_added     = sessions.lines_added + p_lines_added,
            lines_removed   = sessions.lines_removed + p_lines_removed,
            files_touched   = greatest(sessions.files_touched, p_files_touched),
            tokens          = sessions.tokens + p_tokens,
            sources         = array(select distinct unnest from unnest(sessions.sources || array[p_source]) order by 1),
            models          = array(select distinct unnest from unnest(sessions.models  || array[p_model])  order by 1),
            repo_alias      = coalesce(sessions.repo_alias, p_repo_alias),
            git_branch      = coalesce(p_git_branch, sessions.git_branch)
        where id = v_existing.id;

        return v_existing.id;
    else
        -- Insert new session
        insert into sessions (id, user_id, started_at, ended_at, active_duration,
            lines_added, lines_removed, files_touched, tokens,
            sources, models, repo_alias, git_branch)
        values (p_id, v_uid, p_started_at, p_ended_at, p_active_duration,
            p_lines_added, p_lines_removed, p_files_touched, p_tokens,
            array[p_source], array[p_model], p_repo_alias, p_git_branch);

        return p_id;
    end if;
end;
$$;

-- Collapse existing overlapping sessions into merged rows.
-- Run once to clean up the data we already pushed.
do $$
declare
    v_user uuid;
    v_rec  record;
    v_prev_id text := null;
    v_prev_end timestamptz := null;
    v_gap  interval := interval '30 minutes';
begin
    for v_user in select distinct user_id from sessions loop
        v_prev_id := null;
        v_prev_end := null;
        for v_rec in
            select * from sessions
            where user_id = v_user
            order by started_at asc
        loop
            if v_prev_id is not null
               and v_rec.started_at <= v_prev_end + v_gap
            then
                -- Merge v_rec into v_prev
                update sessions set
                    started_at      = least(sessions.started_at, v_rec.started_at),
                    ended_at        = greatest(sessions.ended_at, v_rec.ended_at),
                    active_duration = sessions.active_duration + v_rec.active_duration,
                    lines_added     = sessions.lines_added + v_rec.lines_added,
                    lines_removed   = sessions.lines_removed + v_rec.lines_removed,
                    files_touched   = greatest(sessions.files_touched, v_rec.files_touched),
                    tokens          = sessions.tokens + v_rec.tokens,
                    sources         = array(select distinct unnest from unnest(sessions.sources || v_rec.sources) order by 1),
                    models          = array(select distinct unnest from unnest(sessions.models  || v_rec.models)  order by 1),
                    repo_alias      = coalesce(sessions.repo_alias, v_rec.repo_alias),
                    git_branch      = coalesce(v_rec.git_branch, sessions.git_branch)
                where id = v_prev_id;

                -- Delete the now-merged row
                delete from sessions where id = v_rec.id;

                -- Update prev end time for chaining
                v_prev_end := greatest(v_prev_end, v_rec.ended_at);
            else
                v_prev_id := v_rec.id;
                v_prev_end := v_rec.ended_at;
            end if;
        end loop;
    end loop;
end;
$$;
