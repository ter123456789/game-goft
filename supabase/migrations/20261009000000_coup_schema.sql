-- Coup multiplayer schema.
--
-- Clients only READ, through RLS and Realtime. Every write goes through the
-- game server (service role) via the functions at the bottom, so the rules in
-- packages/coup_domain are the single source of truth.

-- ------------------------------------------------------------------ tables

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z2-9]{6}$'),
  host_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'lobby'
    check (status in ('lobby', 'playing', 'finished')),
  created_at timestamptz not null default now()
);

create table public.room_players (
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 32),
  seat smallint not null check (seat between 0 and 5),
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id),
  unique (room_id, seat)
);

create index room_players_user_id_idx on public.room_players (user_id);

-- The full game, including every hidden card and the deck order.
-- RLS is on and there are no policies: only the service role can see it.
create table public.game_saves (
  room_id uuid primary key references public.rooms (id) on delete cascade,
  state jsonb not null,
  revision integer not null,
  deadline_at timestamptz,
  updated_at timestamptz not null default now()
);

create index game_saves_deadline_idx on public.game_saves (deadline_at)
  where deadline_at is not null;

-- PublicGameView: safe for everyone in the room.
create table public.game_public_state (
  room_id uuid primary key references public.rooms (id) on delete cascade,
  view jsonb not null,
  revision integer not null,
  deadline_at timestamptz,
  updated_at timestamptz not null default now()
);

-- PrivateView: one row per player, readable only by that player.
create table public.player_hands (
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  view jsonb not null,
  revision integer not null,
  updated_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

-- --------------------------------------------------------------------- RLS

-- security definer so the room_players policy can call it without recursing.
create function public.is_room_member(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.room_players
    where room_id = p_room_id and user_id = (select auth.uid())
  );
$$;

alter table public.rooms enable row level security;
alter table public.room_players enable row level security;
alter table public.game_saves enable row level security;
alter table public.game_public_state enable row level security;
alter table public.player_hands enable row level security;

create policy "Members can read their rooms"
  on public.rooms for select to authenticated
  using (public.is_room_member(id));

create policy "Members can read who is in their rooms"
  on public.room_players for select to authenticated
  using (public.is_room_member(room_id));

create policy "Members can read the public game state"
  on public.game_public_state for select to authenticated
  using (public.is_room_member(room_id));

create policy "Players can read only their own hand"
  on public.player_hands for select to authenticated
  using (user_id = (select auth.uid()));

-- RLS already blocks writes (no write policies); revoke as well so a future
-- policy mistake cannot open them up.
revoke insert, update, delete, truncate
  on public.rooms, public.room_players, public.game_saves,
     public.game_public_state, public.player_hands
  from anon, authenticated;
revoke all on public.game_saves from anon, authenticated;

-- ---------------------------------------------------------------- realtime

-- Postgres Changes respects RLS, so each client only receives rows it may read.
alter publication supabase_realtime
  add table public.rooms, public.room_players,
            public.game_public_state, public.player_hands;

-- ------------------------------------------------- server-only functions

create function public.create_room(
  p_host_id uuid,
  p_display_name text,
  p_code text
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_room_id uuid;
begin
  insert into public.rooms (code, host_id)
  values (p_code, p_host_id)
  returning id into v_room_id;

  insert into public.room_players (room_id, user_id, display_name, seat)
  values (v_room_id, p_host_id, p_display_name, 0);

  return v_room_id;
end;
$$;

-- Joining twice is a no-op. Raises room_not_found, room_not_open or room_full.
create function public.join_room(
  p_code text,
  p_user_id uuid,
  p_display_name text
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_room public.rooms;
  v_count integer;
begin
  -- Lock the room so two players joining at once get different seats.
  select * into v_room from public.rooms where code = p_code for update;
  if not found then
    raise exception 'room_not_found';
  end if;

  if exists (
    select 1 from public.room_players
    where room_id = v_room.id and user_id = p_user_id
  ) then
    return v_room.id;
  end if;

  if v_room.status <> 'lobby' then
    raise exception 'room_not_open';
  end if;

  select count(*) into v_count
  from public.room_players where room_id = v_room.id;
  if v_count >= 6 then
    raise exception 'room_full';
  end if;

  insert into public.room_players (room_id, user_id, display_name, seat)
  values (v_room.id, p_user_id, p_display_name, v_count);

  return v_room.id;
end;
$$;

-- Saves the game and every view in one transaction. Returns false, writing
-- nothing, when someone else saved first (optimistic locking on revision).
-- p_expected_revision is null for a brand-new game.
-- p_hands maps user_id -> PrivateView JSON.
create function public.save_game(
  p_room_id uuid,
  p_expected_revision integer,
  p_state jsonb,
  p_revision integer,
  p_deadline_at timestamptz,
  p_public_view jsonb,
  p_hands jsonb,
  p_status text
)
returns boolean
language plpgsql
set search_path = ''
as $$
begin
  if p_expected_revision is null then
    insert into public.game_saves (room_id, state, revision, deadline_at)
    values (p_room_id, p_state, p_revision, p_deadline_at)
    on conflict (room_id) do nothing;
  else
    update public.game_saves
    set state = p_state,
        revision = p_revision,
        deadline_at = p_deadline_at,
        updated_at = now()
    where room_id = p_room_id and revision = p_expected_revision;
  end if;

  if not found then
    return false;
  end if;

  insert into public.game_public_state (room_id, view, revision, deadline_at)
  values (p_room_id, p_public_view, p_revision, p_deadline_at)
  on conflict (room_id) do update
  set view = excluded.view,
      revision = excluded.revision,
      deadline_at = excluded.deadline_at,
      updated_at = now();

  insert into public.player_hands (room_id, user_id, view, revision)
  select p_room_id, hand.key::uuid, hand.value, p_revision
  from jsonb_each(p_hands) as hand
  on conflict (room_id, user_id) do update
  set view = excluded.view,
      revision = excluded.revision,
      updated_at = now();

  update public.rooms
  set status = p_status
  where id = p_room_id and status is distinct from p_status;

  return true;
end;
$$;

revoke execute on function
  public.create_room(uuid, text, text),
  public.join_room(text, uuid, text),
  public.save_game(uuid, integer, jsonb, integer, timestamptz, jsonb, jsonb, text)
  from public, anon, authenticated;

grant execute on function
  public.create_room(uuid, text, text),
  public.join_room(text, uuid, text),
  public.save_game(uuid, integer, jsonb, integer, timestamptz, jsonb, jsonb, text)
  to service_role;
