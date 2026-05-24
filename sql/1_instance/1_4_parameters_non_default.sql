-- parameters (non default)

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
    setting <> boot_val
order by
    category, name;