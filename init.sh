#!/bin/bash
# Generate psql menu/sub-menu files based on the content of SQL_DIR directory

# Vars
DBA_TOOLS="psql-dba-tools"
DBA_TOOLS_REPO="https://github.com/bazaruzero/${DBA_TOOLS}"
DBA_TOOLS_HOME="/home/admin/psql-dba-tools"
SQL_DIR="${DBA_TOOLS_HOME}/sql"
MENU_SCRIPT="${DBA_TOOLS_HOME}/dba.psql"
PSQLRC_FILE="${DBA_TOOLS_HOME}/psqlrc"


# check for scripts
if ! [[ -d ${SQL_DIR} ]]; then
    echo "ERROR: ${SQL_DIR} not found. Please clone latest version of repository using link below:"
    echo "${DBA_TOOLS_REPO}"
    exit 1
fi


# backup current files if any
for file in "${MENU_SCRIPT}" "${PSQLRC_FILE}"; do
    if [[ -f "${file}" ]]; then
        mv "${file}" "${file}_$(date +%Y%m%d)T$(date +%H%M%S)"
    fi
done


# update PSQLRC_FILE
echo "-- ${DBA_TOOLS}" >> ${PSQLRC_FILE}
echo "\set dba '\\\\i ${MENU_SCRIPT}'" >> ${PSQLRC_FILE}


# update MENU_SCRIPT with version info banner
echo "\i ${SQL_DIR}/VERSION.sql" >> ${MENU_SCRIPT}
echo "\echo" >> ${MENU_SCRIPT}


# prepare main menu
echo "\echo 'Menu:'" >> ${MENU_SCRIPT}
dirs=($(find "${SQL_DIR}" -maxdepth 1 -type d -name "[0-9]*_*" | sort -V))

for dir in "${dirs[@]}"; do
    dir_name=$(basename "$dir")
    prefix=${dir_name%%_*}
    name=${dir_name#*_}
    display_name=$(echo "$name" | sed 's/_/ /g')
    display_name=$(echo "$display_name" | sed 's/\b\(.\)/\u\1/g')
    
    # add to main menu
    echo "\echo '  ${prefix} - ${display_name}'" >> ${MENU_SCRIPT}
    
    # create submenu for this directory
    submenu_file="${dir}/sub_menu__${name}.psql"
    
    # get sql files in the directory, sorted by numeric prefix
    sql_files=($(find "${dir}" -maxdepth 1 -type f -name "[0-9]*_*.sql" | sort -V))
    
    # start building submenu
    echo "\\echo" > "${submenu_file}"
    echo "\\echo '===== ${display_name} ====='" >> "${submenu_file}"
    echo "\\echo" >> "${submenu_file}"
    echo "\\echo 'Menu:'" >> "${submenu_file}"
    
    # add menu items for each sql file
    for sql_file in "${sql_files[@]}"; do
        file_name=$(basename "$sql_file")
        file_prefix=$(echo "$file_name" | grep -o '^[0-9_]*[0-9]')
        
        # read first line from SQL file and clean it
        # remove leading/trailing whitespace, remove SQL comments (--), remove quotes
        if [[ -f "$sql_file" ]]; then
            description=$(head -n 1 "$sql_file" | sed 's/^[[:space:]]*--[[:space:]]*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            
            # if description is empty, use filename as fallback
            if [[ -z "$description" ]]; then
                description="${file_name%.sql}"
                description=$(echo "$description" | sed 's/^[0-9_]*_//' | sed 's/_/ /g')
            fi
        else
            description="${file_name%.sql}"
            description=$(echo "$description" | sed 's/^[0-9_]*_//' | sed 's/_/ /g')
        fi
        
        # use just the second number from prefix (e.g., "1" from "1_1", "2" from "1_2")
        menu_number=$(echo "$file_prefix" | awk -F'_' '{print $NF}')
        echo "\\echo '  ${menu_number} - ${description}'" >> "${submenu_file}"
    done
    
    echo "\\echo '  b - Back to main menu'" >> "${submenu_file}"
    echo "\\echo '  q - Quit'" >> "${submenu_file}"
    echo "\\echo" >> "${submenu_file}"
    echo "" >> "${submenu_file}"
    echo "\\echo 'Type your choice and press <Enter>: '" >> "${submenu_file}"
    echo "\\prompt sub_choice" >> "${submenu_file}"
    echo "\\set sc '\'' :sub_choice '\''" >> "${submenu_file}"
    echo "" >> ${submenu_file}
    echo "select" >> ${submenu_file}

    for sql_file in "${sql_files[@]}"; do
        file_name=$(basename "$sql_file")
        file_prefix=$(echo "$file_name" | grep -o '^[0-9_]*[0-9]')
        menu_number=$(echo "$file_prefix" | awk -F'_' '{print $NF}')
        echo "    :sc::text = '${menu_number}' as do_${menu_number}," >> ${submenu_file}
    done

    echo "    :sc::text = 'b' as do_back_to_main," >> ${submenu_file}
    echo "    :sc::text = 'q' as do_quit" >> ${submenu_file}
    echo "\gset" >> ${submenu_file}

    echo "" >> ${submenu_file}
    echo "\if :do_quit" >> ${submenu_file}
    echo "    \echo 'Bye!'" >> ${submenu_file}
    echo "    \echo" >> ${submenu_file}
    echo "\elif :do_back_to_main" >> ${submenu_file}
    echo "    \i ${MENU_SCRIPT}" >> ${submenu_file}

    for sql_file in "${sql_files[@]}"; do
        file_name=$(basename "$sql_file")
        file_prefix=$(echo "$file_name" | grep -o '^[0-9_]*[0-9]')
        menu_number=$(echo "$file_prefix" | awk -F'_' '{print $NF}')
        echo "\elif :do_${menu_number}" >> ${submenu_file}
        echo "    \i ${sql_file}"  >> ${submenu_file}
        echo "    \prompt 'Press <Enter> to continue ...' do_dummy" >> ${submenu_file}
        echo "    \i ${submenu_file}" >> ${submenu_file}
    done

    echo "\else" >> ${submenu_file}
    echo "    \echo" >> ${submenu_file}
    echo "    \echo 'ERROR: Unknown option! Try agan.'" >> ${submenu_file}
    echo "    \echo" >> ${submenu_file}
    echo "    \i ${submenu_file}" >> ${submenu_file}
    echo "\endif" >> ${submenu_file}
done

echo "\echo '  q - Quit'" >> ${MENU_SCRIPT}
echo "\echo" >> ${MENU_SCRIPT}
echo "" >> ${MENU_SCRIPT}
echo "\echo 'Type your choice and press <Enter>: '" >> ${MENU_SCRIPT}
echo "\prompt user_choice" >> ${MENU_SCRIPT}
echo "\set uc '\'' :user_choice '\''" >> ${MENU_SCRIPT}

echo "" >> ${MENU_SCRIPT}
echo "select" >> ${MENU_SCRIPT}

for dir in "${dirs[@]}"; do
    dir_name=$(basename "$dir")
    prefix=${dir_name%%_*}
    echo "    :uc::text = '${prefix}' as do_${prefix}," >> ${MENU_SCRIPT}
done

echo "    :uc::text = 'q' as do_quit" >> ${MENU_SCRIPT}
echo "\gset" >> ${MENU_SCRIPT}

echo "" >> ${MENU_SCRIPT}
echo "\if :do_quit" >> ${MENU_SCRIPT}
echo "    \echo 'Bye!'" >> ${MENU_SCRIPT}
echo "    \echo" >> ${MENU_SCRIPT}

for dir in "${dirs[@]}"; do
    dir_name=$(basename "$dir")
    prefix=${dir_name%%_*}
    name=${dir_name#*_}
    submenu_file="${dir}/sub_menu__${name}.psql"
    echo "\elif :do_${prefix}" >> ${MENU_SCRIPT}
    echo "    \i ${submenu_file}"  >> ${MENU_SCRIPT}  
done

echo "\else" >> ${MENU_SCRIPT}
echo "    \echo" >> ${MENU_SCRIPT}
echo "    \echo 'ERROR: Unknown option! Try agan.'" >> ${MENU_SCRIPT}
echo "    \echo" >> ${MENU_SCRIPT}
echo "    \i ${MENU_SCRIPT}" >> ${MENU_SCRIPT}
echo "\endif" >> ${MENU_SCRIPT}