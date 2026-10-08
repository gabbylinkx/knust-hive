-- Keep chat attachments private and readable only by members of the chat.
-- Uploads are stored under <chat-id>/<sender-id>/<generated-name>.
alter table public.messages
  add column if not exists message_type text not null default 'text'
    check (message_type in ('text', 'image', 'video', 'audio', 'file')),
  add column if not exists attachment_path text,
  add column if not exists file_name text,
  add column if not exists mime_type text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.messages'::regclass
      and conname = 'messages_attachment_metadata_check'
  ) then
    alter table public.messages
      add constraint messages_attachment_metadata_check
      check (
        (message_type = 'text' and attachment_path is null)
        or (message_type <> 'text' and attachment_path is not null)
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.messages'::regclass
      and conname = 'messages_id_chat_id_key'
  ) then
    alter table public.messages
      add constraint messages_id_chat_id_key unique (id, chat_id);
  end if;
end;
$$;

drop policy if exists "messages insertable only by chat members"
  on public.messages;
create policy "messages insertable only by chat members"
  on public.messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_chat_member(chat_id)
    and (
      attachment_path is null
      or (
        (storage.foldername(attachment_path))[1] = chat_id::text
        and (storage.foldername(attachment_path))[2] = auth.uid()::text
      )
    )
  );

drop policy if exists "senders delete their own chat messages"
  on public.messages;
create policy "senders delete their own chat messages"
  on public.messages for delete to authenticated
  using (
    sender_id = auth.uid()
    and public.is_chat_member(chat_id)
  );
grant delete on public.messages to authenticated;

create table if not exists public.message_reactions (
  id uuid primary key default uuid_generate_v4(),
  message_id uuid not null,
  chat_id uuid not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check (emoji in ('❤️', '😂', '😮', '😢', '🔥', '👍')),
  created_at timestamptz not null default now(),
  unique (message_id, user_id, emoji),
  foreign key (message_id, chat_id)
    references public.messages(id, chat_id) on delete cascade
);

create index if not exists message_reactions_chat_id_idx
  on public.message_reactions(chat_id, message_id);

alter table public.message_reactions enable row level security;

drop policy if exists "chat members read message reactions"
  on public.message_reactions;
create policy "chat members read message reactions"
  on public.message_reactions for select to authenticated
  using (public.is_chat_member(chat_id));

drop policy if exists "chat members add their own message reactions"
  on public.message_reactions;
create policy "chat members add their own message reactions"
  on public.message_reactions for insert to authenticated
  with check (
    user_id = auth.uid()
    and public.is_chat_member(chat_id)
  );

drop policy if exists "students remove their own message reactions"
  on public.message_reactions;
create policy "students remove their own message reactions"
  on public.message_reactions for delete to authenticated
  using (user_id = auth.uid() and public.is_chat_member(chat_id));

grant select, insert, delete on public.message_reactions to authenticated;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'chat-media',
  'chat-media',
  false,
  26214400,
  array[
    'image/jpeg', 'image/png', 'image/gif', 'image/webp',
    'video/mp4', 'video/webm', 'video/quicktime',
    'audio/mpeg', 'audio/mp4', 'audio/ogg', 'audio/webm', 'audio/wav',
    'application/pdf', 'text/plain', 'text/csv',
    'application/rtf', 'application/zip',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation'
  ]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "chat members upload their own media"
  on storage.objects;
create policy "chat members upload their own media"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'chat-media'
    and (storage.foldername(name))[2] = auth.uid()::text
    and public.is_chat_member((storage.foldername(name))[1]::uuid)
  );

drop policy if exists "chat members read chat media"
  on storage.objects;
create policy "chat members read chat media"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'chat-media'
    and public.is_chat_member((storage.foldername(name))[1]::uuid)
  );

drop policy if exists "senders delete their own chat media"
  on storage.objects;
create policy "senders delete their own chat media"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'chat-media'
    and (storage.foldername(name))[2] = auth.uid()::text
    and public.is_chat_member((storage.foldername(name))[1]::uuid)
  );

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_reactions'
  ) then
    alter publication supabase_realtime
      add table public.message_reactions;
  end if;
end;
$$;

notify pgrst, 'reload schema';
