-- vacuum (extended with queue)

--
-- https://postgres.ai/docs/postgres-howtos/database-administration/maintenance/autovacuum-queue-and-progress
-- https://gitlab.com/-/snippets/1889668
--

with table_opts as (
  select
    pg_class.oid,
    relname,
    nspname,
    array_to_string(reloptions, '') as relopts
  from pg_class
  join pg_namespace as ns on relnamespace = ns.oid
), vacuum_settings as (
  select
    oid,
    relname,
    nspname,
    case
      when relopts like '%autovacuum_vacuum_threshold%'
        then regexp_replace(relopts, '.*autovacuum_vacuum_threshold=([0-9.]+).*', e'\\1')::int8
      else current_setting('autovacuum_vacuum_threshold')::int8
    end as autovacuum_vacuum_threshold,
    case
      when relopts like '%autovacuum_vacuum_scale_factor%'
        then regexp_replace(relopts, '.*autovacuum_vacuum_scale_factor=([0-9.]+).*', e'\\1')::numeric
      else current_setting('autovacuum_vacuum_scale_factor')::numeric
    end as autovacuum_vacuum_scale_factor,
    case
      when relopts ~ 'autovacuum_enabled=(false|off)' then false
      else true
    end as autovacuum_enabled
  from table_opts
), progress as (
  select *
  from pg_stat_progress_vacuum
)
select
  coalesce(
    coalesce(nullif(vacuum_settings.nspname, 'public') || '.', '') || vacuum_settings.relname, -- current DB
    format('[something in "%I"]', progress.datname) -- another DB
  ) as relation,
  round((100 * psat.n_dead_tup::numeric / nullif(pg_class.reltuples, 0))::numeric, 2) as dead_tup_pct,
  pg_class.reltuples::numeric,
  psat.n_dead_tup,
  format(
    'vt: %s, vsf: %s, %s', -- 'vt' – vacuum_threshold, 'vsf' – vacuum_scale_factor
    vacuum_settings.autovacuum_vacuum_threshold,
    vacuum_settings.autovacuum_vacuum_scale_factor,
    case when autovacuum_enabled then 'enabled' else 'DISABLED' end
  ) as effective_settings,
  case
    when last_autovacuum > coalesce(last_vacuum, '0001-01-01') then left(last_autovacuum::text, 19) || ' (auto)'
    when last_vacuum is not null then left(last_vacuum::text, 19) || ' (manual)'
    else null
  end as last_vacuumed,
  coalesce(progress.phase, '~~~ in queue ~~~') as status,
  progress.pid,
  case
    when activity.query ~ '^autovacuum.*to prevent wraparound' then 'wraparound'
    when activity.query ~ '^vacuum' then 'user'
    when activity.pid is null then null
    else 'regular'
  end as mode,
  case
    when activity.pid is null then null
    else coalesce(wait_event_type || '.' || wait_event, 'f')
  end as waiting,
  round(100.0 * progress.heap_blks_scanned / nullif(progress.heap_blks_total, 0), 1) as scanned_pct,
  round(100.0 * progress.heap_blks_vacuumed / nullif(progress.heap_blks_total, 0), 1) as vacuumed_pct,
  progress.index_vacuum_count,
  case
    when psat.relid is not null and progress.relid is not null
      then (select count(*) from pg_index where indrelid = psat.relid)
    else null
  end as index_count
from pg_stat_all_tables as psat
join pg_class on psat.relid = pg_class.oid
left join vacuum_settings on pg_class.oid = vacuum_settings.oid
full outer join progress
  on progress.relid = psat.relid
  and progress.datname = current_database()
left join pg_stat_activity as activity using (pid)
where
  psat.relid is null
  or progress.phase is not null
  or (
    autovacuum_vacuum_threshold + (autovacuum_vacuum_scale_factor::numeric * pg_class.reltuples)
      < psat.n_dead_tup
  )
order by status, relation;
