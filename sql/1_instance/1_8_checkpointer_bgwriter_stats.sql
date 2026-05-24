-- checkpointer / bgwriter / backends write stats
-- Ref. to https://gitlab.com/gitlab-com/gl-infra/production-engineering/-/issues/12867

\echo ''
\echo '>>> Settings:'
\echo ''

select
    name,
    setting,
    unit,
    context
from
    pg_settings
where
    category in ('Write-Ahead Log / Checkpoints','Resource Usage / Background Writer')
order by
    category, name;

\echo ''
\echo '>> Stats:'
\echo ''

select
    stats_reset,
    --checkpoints_timed,
    round(100 * checkpoints_timed::numeric  / nullif((checkpoints_timed + checkpoints_req),0), 2) || '%' as checkpoint_timed,
    --checkpoints_req,
    round(100 * checkpoints_req::numeric  / nullif((checkpoints_timed + checkpoints_req),0), 2) || '%' as checkpoint_req,
    --buffers_checkpoint,
    round(100 * buffers_checkpoint::numeric  / nullif((buffers_checkpoint + buffers_clean + buffers_backend),0), 2) || '%' as checkpoint_written,
    --buffers_clean,
    round(100 * buffers_clean::numeric  / nullif((buffers_checkpoint + buffers_clean + buffers_backend),0), 2) || '%' as bgwriter_written,
    --buffers_backend,
    round(100 * buffers_backend::numeric  / nullif((buffers_checkpoint + buffers_clean + buffers_backend),0), 2) || '%' as backends_written,
    --buffers_backend_fsync,
    round(100 * buffers_backend_fsync::numeric  / nullif((buffers_checkpoint + buffers_clean + buffers_backend),0), 2) || '%' as backends_fsync,
    pg_size_pretty((buffers_checkpoint + buffers_clean + buffers_backend) * current_setting('block_size')::integer /
        (EXTRACT (EPOCH FROM current_timestamp - stats_reset))::bigint) || ' / s' as size
from
    pg_stat_bgwriter;



