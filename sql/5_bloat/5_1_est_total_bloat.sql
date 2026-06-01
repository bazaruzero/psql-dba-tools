-- total bloat estimation
-- Combines table and index bloat statistics to provide overall database metrics
-- Based on table_bloat.sql and btree_bloat.sql from ioguix/pgsql-bloat-estimation
--
-- Output fields:
-- db_size: total database size (tables + indexes)
-- db_extra_size: total extra space (tables + indexes)
-- db_extra_pct: percentage of extra space
-- db_bloat_size: total bloat size (tables + indexes)
-- db_bloat_pct: percentage of bloat

--
-- Ref. to https://github.com/ioguix/pgsql-bloat-estimation
--

\echo ''
\echo '##'
\echo '## NOTE: All numbers are estimates, not exact.'
\echo '##       Run "ANALYZE;" before this query to get more precise results.'
\echo '##'
\echo ''

WITH table_stats AS (
    -- Get aggregated table statistics
    SELECT 
        SUM((final.bs*final.tblpages)::bigint) AS real_size_bytes,
        SUM(((final.tblpages-final.est_tblpages)*final.bs)::bigint) AS extra_size_bytes,
        AVG(CASE WHEN final.tblpages > 0 AND final.tblpages - final.est_tblpages > 0
            THEN 100 * (final.tblpages - final.est_tblpages)/final.tblpages::float
            ELSE 0
        END) AS extra_pct,
        SUM((CASE WHEN final.tblpages - final.est_tblpages_ff > 0
            THEN (final.tblpages-final.est_tblpages_ff)*final.bs
            ELSE 0
        END)::bigint) AS bloat_size_bytes,
        AVG(CASE WHEN final.tblpages > 0 AND final.tblpages - final.est_tblpages_ff > 0
            THEN 100 * (final.tblpages - final.est_tblpages_ff)/final.tblpages::float
            ELSE 0
        END) AS bloat_pct
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
                    AND tbl.relkind in ('r','t','m')
                    AND ns.nspname NOT IN ('pg_catalog', 'information_schema')
                    AND ns.nspname NOT LIKE 'pg_temp%'
                    AND ns.nspname NOT LIKE 'pg_toast_temp%'
                GROUP BY 1,2,3,4,5,6,7,8,9,10
            ) AS s
        ) AS s2
    ) AS final
    WHERE 1=1
    HAVING SUM((final.tblpages-final.est_tblpages_ff)*final.bs) > 0
),
index_stats AS (
    -- Get aggregated index statistics (BTREE only)
    SELECT 
        COALESCE(SUM(real_size_bytes), 0)::bigint AS real_size_bytes,
        COALESCE(SUM(extra_size_bytes), 0)::bigint AS extra_size_bytes,
        COALESCE(AVG(extra_pct), 0) AS extra_pct,
        COALESCE(SUM(bloat_size_bytes), 0)::bigint AS bloat_size_bytes,
        COALESCE(AVG(bloat_pct), 0) AS bloat_pct
    FROM (
        SELECT 
            bs*(relpages)::bigint AS real_size_bytes,
            GREATEST(0, bs*(relpages-est_pages)::bigint) AS extra_size_bytes,
            GREATEST(0, 100 * (relpages-est_pages)::float / NULLIF(relpages, 0)) AS extra_pct,
            GREATEST(0, (CASE WHEN relpages > est_pages_ff
                THEN bs*(relpages-est_pages_ff)
                ELSE 0
            END)::bigint) AS bloat_size_bytes,
            GREATEST(0, 100 * (relpages-est_pages_ff)::float / NULLIF(relpages, 0)) AS bloat_pct
        FROM (
            SELECT coalesce(1 +
                ceil(reltuples/floor((bs-pageopqdata-pagehdr)/(4+nulldatahdrwidth)::float)), 0
                ) AS est_pages,
                coalesce(1 +
                    ceil(reltuples/floor((bs-pageopqdata-pagehdr)*fillfactor/(100*(4+nulldatahdrwidth)::float))), 0
                ) AS est_pages_ff,
                bs, relpages, fillfactor, reltuples, is_na
            FROM (
                SELECT maxalign, bs, nspname, tblname, idxname, reltuples, relpages, idxoid, fillfactor,
                    ( index_tuple_hdr_bm +
                        maxalign - CASE
                            WHEN index_tuple_hdr_bm%maxalign = 0 THEN maxalign
                            ELSE index_tuple_hdr_bm%maxalign
                        END
                        + nulldatawidth + maxalign - CASE
                            WHEN nulldatawidth = 0 THEN 0
                            WHEN nulldatawidth::integer%maxalign = 0 THEN maxalign
                            ELSE nulldatawidth::integer%maxalign
                        END
                    )::numeric AS nulldatahdrwidth, pagehdr, pageopqdata, is_na
                FROM (
                    SELECT n.nspname, i.tblname, i.idxname, i.reltuples, i.relpages,
                        i.idxoid, i.fillfactor, current_setting('block_size')::numeric AS bs,
                        CASE
                            WHEN version() ~ 'mingw32' OR version() ~ '64-bit|x86_64|ppc64|ia64|amd64' THEN 8
                            ELSE 4
                        END AS maxalign,
                        24 AS pagehdr,
                        16 AS pageopqdata,
                        CASE WHEN max(coalesce(s.null_frac,0)) = 0
                            THEN 8
                            ELSE 8 + (( 32 + 8 - 1 ) / 8)
                        END AS index_tuple_hdr_bm,
                        sum( (1-coalesce(s.null_frac, 0)) * coalesce(s.avg_width, 1024)) AS nulldatawidth,
                        max( CASE WHEN i.atttypid = 'pg_catalog.name'::regtype THEN 1 ELSE 0 END ) > 0 AS is_na
                    FROM (
                        SELECT ct.relname AS tblname, ct.relnamespace, ic.idxname, ic.attpos, ic.indkey, ic.indkey[ic.attpos], ic.reltuples, ic.relpages, ic.tbloid, ic.idxoid, ic.fillfactor,
                            coalesce(a1.attnum, a2.attnum) AS attnum, coalesce(a1.attname, a2.attname) AS attname, coalesce(a1.atttypid, a2.atttypid) AS atttypid,
                            CASE WHEN a1.attnum IS NULL
                            THEN ic.idxname
                            ELSE ct.relname
                            END AS attrelname
                        FROM (
                            SELECT idxname, reltuples, relpages, tbloid, idxoid, fillfactor, indkey,
                                pg_catalog.generate_series(1,indnatts) AS attpos
                            FROM (
                                SELECT ci.relname AS idxname, ci.reltuples, ci.relpages, i.indrelid AS tbloid,
                                    i.indexrelid AS idxoid,
                                    coalesce(substring(
                                        array_to_string(ci.reloptions, ' ')
                                        from 'fillfactor=([0-9]+)')::smallint, 90) AS fillfactor,
                                    i.indnatts,
                                    pg_catalog.string_to_array(pg_catalog.textin(
                                        pg_catalog.int2vectorout(i.indkey)),' ')::int[] AS indkey
                                FROM pg_catalog.pg_index i
                                JOIN pg_catalog.pg_class ci ON ci.oid = i.indexrelid
                                WHERE ci.relam=(SELECT oid FROM pg_am WHERE amname = 'btree')
                                AND ci.relpages > 0
                            ) AS idx_data
                        ) AS ic
                        JOIN pg_catalog.pg_class ct ON ct.oid = ic.tbloid
                        LEFT JOIN pg_catalog.pg_attribute a1 ON
                            ic.indkey[ic.attpos] <> 0
                            AND a1.attrelid = ic.tbloid
                            AND a1.attnum = ic.indkey[ic.attpos]
                        LEFT JOIN pg_catalog.pg_attribute a2 ON
                            ic.indkey[ic.attpos] = 0
                            AND a2.attrelid = ic.idxoid
                            AND a2.attnum = ic.attpos
                    ) i
                    JOIN pg_catalog.pg_namespace n ON n.oid = i.relnamespace
                    JOIN pg_catalog.pg_stats s ON s.schemaname = n.nspname
                                            AND s.tablename = i.attrelname
                                            AND s.attname = i.attname
                    WHERE 1=1
                        AND n.nspname NOT IN ('pg_catalog', 'information_schema')
                        AND n.nspname NOT LIKE 'pg_temp%'
                        AND n.nspname NOT LIKE 'pg_toast_temp%'
                    GROUP BY 1,2,3,4,5,6,7,8,9,10,11
                ) AS rows_data_stats
            ) AS rows_hdr_pdg_stats
        ) AS relation_stats
        WHERE is_na = false
        AND relpages > 0
        AND relpages > 10
        AND (CASE WHEN relpages > est_pages_ff THEN bs*(relpages-est_pages_ff) ELSE 0 END)::bigint > 0
    ) AS idx_stats
),
combined_stats AS (
    -- Combine table and index statistics
    SELECT
        COALESCE((SELECT real_size_bytes FROM table_stats), 0) AS table_real_size,
        COALESCE((SELECT real_size_bytes FROM index_stats), 0) AS index_real_size,
        COALESCE((SELECT extra_size_bytes FROM table_stats), 0) AS table_extra_size,
        COALESCE((SELECT extra_size_bytes FROM index_stats), 0) AS index_extra_size,
        COALESCE((SELECT bloat_size_bytes FROM table_stats), 0) AS table_bloat_size,
        COALESCE((SELECT bloat_size_bytes FROM index_stats), 0) AS index_bloat_size
)
SELECT
    current_database() as db,
    -- Total database size
    pg_size_pretty(table_real_size + index_real_size) AS db_size,
    -- Total extra space (alignment padding + overhead)
    pg_size_pretty(table_extra_size + index_extra_size) AS db_extra_size,
    -- Percentage of extra space (weighted average)
    ROUND(
        CASE WHEN (table_real_size + index_real_size) > 0 
            THEN 100.0 * (table_extra_size + index_extra_size) / (table_real_size + index_real_size)
            ELSE 0
        END, 2
    ) AS db_extra_pct,
    -- Total bloat size
    pg_size_pretty(table_bloat_size + index_bloat_size) AS db_bloat_size,
    -- Percentage of bloat (weighted average)
    ROUND(
        CASE WHEN (table_real_size + index_real_size) > 0 
            THEN 100.0 * (table_bloat_size + index_bloat_size) / (table_real_size + index_real_size)
            ELSE 0
        END, 2
    ) AS db_bloat_pct
FROM combined_stats;