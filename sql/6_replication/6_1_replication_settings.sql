-- replication settings

select
    category,
    name,
    setting,
    unit, 
    case 
        when context = 'postmaster' then 'true'
        else 'false'
    end as is_instance_restart_required,
    context
from
    pg_settings
where
    lower(category) like '%replication%'
    or category = 'Write-Ahead Log / Recovery'
order by
    category, name;