-- Add cli_version column so the iOS app can compare the user's installed
-- CLI version against the latest GitHub release.

alter table installations add column if not exists cli_version text;

-- Recreate upsert_installation to accept and store the version string.
create or replace function upsert_installation(p_hostname text, p_cli_version text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if auth.uid() is null then
        raise exception 'not authenticated';
    end if;

    insert into installations (user_id, hostname, cli_version)
    values (auth.uid(), p_hostname, p_cli_version)
    on conflict (user_id, hostname) do update
        set last_seen_at = now(),
            cli_version = coalesce(excluded.cli_version, installations.cli_version);
end;
$$;

revoke all on function upsert_installation(text, text) from public;
grant execute on function upsert_installation(text, text) to authenticated;
