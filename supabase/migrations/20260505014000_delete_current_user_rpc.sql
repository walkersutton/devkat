-- Let an authenticated user permanently delete their own account and data.
-- This must run server-side because deleting from auth.users requires elevated
-- database privileges.

create or replace function delete_current_user()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
    v_uid uuid := auth.uid();
begin
    if v_uid is null then
        raise exception 'delete_current_user requires an authenticated user';
    end if;

    delete from public.session_components
    where user_id = v_uid;

    delete from public.sessions
    where user_id = v_uid;

    delete from auth.users
    where id = v_uid;
end;
$$;

revoke all on function delete_current_user() from public;
grant execute on function delete_current_user() to authenticated;
