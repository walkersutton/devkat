-- Stores in-app review prompt interactions and user feedback.

create table if not exists feedback (
    id          uuid        primary key default gen_random_uuid(),
    user_id     uuid        references auth.users on delete cascade not null default auth.uid(),
    kind        text        not null,
    message     text,
    app_version text,
    created_at  timestamptz not null default now(),
    constraint feedback_kind_check check (
        kind in ('review_positive', 'review_negative')
    )
);

alter table feedback enable row level security;

create policy "Users can read own feedback"
    on feedback for select
    using (auth.uid() = user_id);

create policy "Users can insert own feedback"
    on feedback for insert
    with check (auth.uid() = user_id);

create index if not exists feedback_user_created
    on feedback (user_id, created_at desc);
