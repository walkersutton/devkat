-- Add source column to track which AI tool generated the session
-- Values: 'claude' | 'codex' | 'cursor'
alter table sessions
    add column source text not null default 'claude'
        check (source in ('claude', 'codex', 'cursor'));

create index sessions_user_source on sessions (user_id, source);
