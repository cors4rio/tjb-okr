-- Rode isto uma vez em: Supabase Dashboard > seu projeto > SQL Editor > New query > Run
-- Antes de rodar, troque 'TROQUE-ESTA-SENHA-AQUI' pela senha que só você vai saber.

-- 1) Tabela com o estado publicado do OKR (uma única linha, id fixo = 1)
create table if not exists public.okr_state (
  id int primary key default 1,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  constraint okr_state_single_row check (id = 1)
);

insert into public.okr_state (id, data)
values (1, '{}'::jsonb)
on conflict (id) do nothing;

alter table public.okr_state enable row level security;

create policy "leitura publica do okr_state"
  on public.okr_state for select
  using (true);
-- Sem policy de insert/update/delete: ninguém escreve direto na tabela,
-- só a função publish_okr_state abaixo (que roda com privilégio elevado).

-- 2) Tabela de configuração interna — RLS ativo e ZERO policies:
--    ninguém consegue ler isso via API, nem com a chave pública.
create table if not exists public.app_settings (
  key text primary key,
  value text not null
);
alter table public.app_settings enable row level security;

insert into public.app_settings (key, value)
values ('publish_passphrase', 'TROQUE-ESTA-SENHA-AQUI')
on conflict (key) do update set value = excluded.value;

-- 3) Função que confere a senha e publica o novo estado.
--    SECURITY DEFINER roda com privilégio do dono, ignorando as RLS acima
--    só dentro da própria função — é assim que ela consegue ler app_settings
--    e escrever em okr_state mesmo as duas estando travadas por fora.
create or replace function public.publish_okr_state(new_data jsonb, passphrase text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  correct text;
begin
  select value into correct from public.app_settings where key = 'publish_passphrase';
  if correct is null or passphrase <> correct then
    raise exception 'senha incorreta';
  end if;
  update public.okr_state set data = new_data, updated_at = now() where id = 1;
end;
$$;

grant execute on function public.publish_okr_state(jsonb, text) to anon, authenticated;
