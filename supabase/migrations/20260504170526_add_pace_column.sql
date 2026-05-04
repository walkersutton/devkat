-- Add pace as a generated column: (lines_added + lines_removed) / hours
-- Postgres computes and stores this automatically — no CLI or app changes needed.

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
