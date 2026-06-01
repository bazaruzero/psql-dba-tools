-- estimated total tables bloat (excludes catalog tables)

--
-- Ref. to https://github.com/ioguix/pgsql-bloat-estimation/blob/master/table/table_bloat.sql
--

\echo ''
\echo '##'
\echo '## NOTE: All numbers are estimates, not exact.'
\echo '##       Run "ANALYZE [table_name]" before this query to get more precise results for specific tables or the whole database.'
\echo '##'
\echo ''

SELECT 
  pg_size_pretty(SUM((final.bs*final.tblpages)::bigint)::bigint) AS total_real_size,
  pg_size_pretty(SUM(((final.tblpages-final.est_tblpages)*final.bs)::bigint)::bigint) AS total_extra_size,
  ROUND(AVG(CASE WHEN final.tblpages > 0 AND final.tblpages - final.est_tblpages > 0
    THEN 100 * (final.tblpages - final.est_tblpages)/final.tblpages::float
    ELSE 0
  END)::numeric, 2) AS avg_extra_pct,
  pg_size_pretty(SUM((CASE WHEN final.tblpages - final.est_tblpages_ff > 0
    THEN (final.tblpages-final.est_tblpages_ff)*final.bs
    ELSE 0
  END)::bigint)::bigint) AS total_bloat_size,
  ROUND(AVG(CASE WHEN final.tblpages > 0 AND final.tblpages - final.est_tblpages_ff > 0
    THEN 100 * (final.tblpages - final.est_tblpages_ff)/final.tblpages::float
    ELSE 0
  END)::numeric, 2) AS avg_bloat_pct,
  COUNT(*) AS total_tables_count
FROM (
  SELECT ceil( reltuples / ( (bs-page_hdr)/tpl_size ) ) + ceil( toasttuples / 4 ) AS est_tblpages,
    ceil( reltuples / ( (bs-page_hdr)*fillfactor/(tpl_size*100) ) ) + ceil( toasttuples / 4 ) AS est_tblpages_ff,
    tblpages, fillfactor, bs, tblid, schemaname, tblname, heappages, toastpages, is_na, reltuples
  FROM (
    SELECT
      ( 4 + tpl_hdr_size + tpl_data_size + (2*ma)
        - CASE WHEN tpl_hdr_size%ma = 0 THEN ma ELSE tpl_hdr_size%ma END
        - CASE WHEN ceil(tpl_data_size)::int%ma = 0 THEN ma ELSE ceil(tpl_data_size)::int%ma END
      ) AS tpl_size, bs - page_hdr AS size_per_block, (heappages + toastpages) AS tblpages, heappages,
      toastpages, reltuples, toasttuples, bs, page_hdr, tblid, schemaname, tblname, fillfactor, is_na
    FROM (
      SELECT
        tbl.oid AS tblid, ns.nspname AS schemaname, tbl.relname AS tblname, tbl.reltuples,
        tbl.relpages AS heappages, coalesce(toast.relpages, 0) AS toastpages,
        coalesce(toast.reltuples, 0) AS toasttuples,
        coalesce(substring(
          array_to_string(tbl.reloptions, ' ')
          FROM 'fillfactor=([0-9]+)')::smallint, 100) AS fillfactor,
        current_setting('block_size')::numeric AS bs,
        CASE WHEN version()~'mingw32' OR version()~'64-bit|x86_64|ppc64|ia64|amd64' THEN 8 ELSE 4 END AS ma,
        24 AS page_hdr,
        23 + CASE WHEN MAX(coalesce(s.null_frac,0)) > 0 THEN ( 7 + count(s.attname) ) / 8 ELSE 0::int END
           + CASE WHEN bool_or(att.attname = 'oid' and att.attnum < 0) THEN 4 ELSE 0 END AS tpl_hdr_size,
        sum( (1-coalesce(s.null_frac, 0)) * coalesce(s.avg_width, 0) ) AS tpl_data_size,
        bool_or(att.atttypid = 'pg_catalog.name'::regtype)
          OR sum(CASE WHEN att.attnum > 0 THEN 1 ELSE 0 END) <> count(s.attname) AS is_na
      FROM pg_attribute AS att
        JOIN pg_class AS tbl ON att.attrelid = tbl.oid
        JOIN pg_namespace AS ns ON ns.oid = tbl.relnamespace
        LEFT JOIN pg_stats AS s ON s.schemaname=ns.nspname
          AND s.tablename = tbl.relname AND s.inherited=false AND s.attname=att.attname
        LEFT JOIN pg_class AS toast ON tbl.reltoastrelid = toast.oid
      WHERE NOT att.attisdropped
        ---------- FILTER HERE ----------
        AND tbl.relkind in ('r','t','m')
        AND ns.nspname NOT IN ('pg_catalog', 'information_schema')
        AND ns.nspname NOT LIKE 'pg_temp%'
        AND ns.nspname NOT LIKE 'pg_toast_temp%'
        ---------------------------------
      GROUP BY 1,2,3,4,5,6,7,8,9,10
    ) AS s
  ) AS s2
) AS final
WHERE 1=1
  --AND NOT final.is_na
HAVING SUM((final.tblpages-final.est_tblpages_ff)*final.bs) > 0;