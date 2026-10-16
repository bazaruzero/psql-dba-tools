-- top indexes

with index_data as (
    select
        c.relnamespace::regnamespace::text as idx_schema,
        t.relname as idx_table,
        c.relname as idx_name,
        am.amname as idx_type,
        case c.relkind
            when 'i' then 'local'
            when 'G' then 'global'
            else c.relkind::text
        end as idx_kind,
        pg_total_relation_size(c.oid) as idx_size_bytes,
        i.indrelid as idx_table_oid
    from
        pg_class c
        join pg_am am on c.relam = am.oid
        join pg_index i on i.indexrelid = c.oid
        join pg_class t on t.oid = i.indrelid
    where
        c.relkind in ('i', 'G')
),
table_subtree_sizes as (
    select
        tt.oid as t_oid,
        coalesce(
            case
                when tt.relkind = 'p' then (
                    select coalesce(sum(
                        case
                            when node_t.reltoastrelid = 0 then pg_total_relation_size(node_t.oid) - pg_indexes_size(node_t.oid)
                            else pg_total_relation_size(node_t.oid) - pg_indexes_size(node_t.oid) - pg_total_relation_size(node_t.reltoastrelid)
                        end
                    ), 0)::bigint
                    from pg_partition_tree(tt.oid) pt
                    join pg_class node_t on node_t.oid = pt.relid
                )
                else (
                    case
                        when tt.reltoastrelid = 0 then pg_total_relation_size(tt.oid) - pg_indexes_size(tt.oid)
                        else pg_total_relation_size(tt.oid) - pg_indexes_size(tt.oid) - pg_total_relation_size(tt.reltoastrelid)
                    end
                )
            end, 0
        )::bigint as table_size_bytes
    from
        (select distinct idx_table_oid as oid from index_data) uniq
        join pg_class tt on tt.oid = uniq.oid
),
schema_object_sizes as (
    select
        n.nspname as schema_name,
        coalesce(
            case
                when sc.relkind = 'p' then (
                    select sum(pg_total_relation_size(pt.relid))
                    from pg_partition_tree(sc.oid) pt
                )
                else pg_total_relation_size(sc.oid)
            end, 0
        )::bigint as obj_size_bytes
    from pg_class sc
    join pg_namespace n on sc.relnamespace = n.oid
    where sc.relispartition = false
),
schema_totals as (
    select
        schema_name,
        sum(obj_size_bytes)::bigint as schema_size_bytes
    from schema_object_sizes
    group by schema_name
),
db_total as (
    select pg_database_size(current_database()) as db_size_bytes
)
select
    id.idx_schema,
    id.idx_table,
    id.idx_name,
    id.idx_type,
    id.idx_kind,
    pg_size_pretty(id.idx_size_bytes) as idx_size,
    round(100.0 * id.idx_size_bytes / nullif(ts.table_size_bytes, 0), 2) as idx_table_ratio,
    pg_size_pretty(ts.table_size_bytes) as idx_table_size,
    round(100.0 * id.idx_size_bytes / nullif(st.schema_size_bytes, 0), 2) as idx_schema_ratio,
    pg_size_pretty(st.schema_size_bytes) as idx_schema_size,
    round(100.0 * id.idx_size_bytes / nullif(dt.db_size_bytes, 0), 2) as idx_db_ratio,
    pg_size_pretty(dt.db_size_bytes) as idx_db_size
from
    index_data id
    join table_subtree_sizes ts on ts.t_oid = id.idx_table_oid
    join schema_totals st on st.schema_name = id.idx_schema
    cross join db_total dt
order by
    id.idx_size_bytes desc
limit 10;