#!/bin/bash
# Generate psql menu/sub-menu files based on the content of SQL_DIR directory

set -e

##############################
## Config
##############################

# Name
DBA_TOOLS="psql-dba-tools"

# Paths
DBA_TOOLS_REPO="https://github.com/bazaruzero/${DBA_TOOLS}"
DBA_TOOLS_HOME="${HOME}/${DBA_TOOLS}"
SQL_DIR="${DBA_TOOLS_HOME}/sql"
CUSTOM_DIR="${SQL_DIR}/custom"
MENU_SCRIPT="${DBA_TOOLS_HOME}/dba.psql"
PSQLRC_FILE="${DBA_TOOLS_HOME}/psqlrc"

##############################
## Helper Functions
##############################

# Check if path is a valid symlink pointing to a directory
is_valid_symlink_to_dir() {
    local path="$1"
    if [[ -L "$path" ]] && [[ -d "$path" ]]; then
        return 0
    else
        return 1
    fi
}

# Generate submenu for a custom directory (symlink target)
generate_custom_submenu() {
    local custom_link="$1"
    local custom_link_name=$(basename "$custom_link")
    local target_dir=$(readlink -f "$custom_link")
    local submenu_file="${CUSTOM_DIR}/sub_menu__${custom_link_name}.psql"
    
    # Get all SQL files in the target directory (any name pattern)
    # Using while loop with null delimiter to handle special characters in filenames
    local sql_files=()
    while IFS= read -r -d '' file; do
        sql_files+=("$file")
    done < <(find "$target_dir" -maxdepth 1 -type f -name "*.sql" -print0 | sort -V -z)
    
    # Skip if no SQL files found
    if [[ ${#sql_files[@]} -eq 0 ]]; then
        echo "Warning: No SQL files found in ${target_dir} (linked from ${custom_link_name})"
        return
    fi
    
    # Start building submenu
    echo "\\echo" > "$submenu_file"
    echo "\\echo '===== Custom: ${custom_link_name} ====='" >> "$submenu_file"
    echo "\\echo" >> "$submenu_file"
    echo "\\echo 'Menu:'" >> "$submenu_file"
    
    # Add menu items for each SQL file (numbered sequentially)
    # Use filename as is, without any processing
    local menu_index=1
    for sql_file in "${sql_files[@]}"; do
        local file_name=$(basename "$sql_file")
        echo "\\echo '  ${menu_index} - ${file_name}'" >> "$submenu_file"
        menu_index=$((menu_index + 1))
    done
    
    echo "\\echo '  b - back to main menu'" >> "$submenu_file"
    echo "\\echo '  q - quit'" >> "$submenu_file"
    echo "\\echo" >> "$submenu_file"
    echo "" >> "$submenu_file"
    echo "\\prompt 'Type your choice and press <Enter>: ' sub_choice" >> "$submenu_file"
    echo "\\set sc '\'' :sub_choice '\''" >> "$submenu_file"
    echo "" >> "$submenu_file"
    echo "select" >> "$submenu_file"
    
    # Generate SELECT conditions for each menu option
    local select_index=1
    for sql_file in "${sql_files[@]}"; do
        echo "    :sc::text = '${select_index}' as do_${custom_link_name}_${select_index}," >> "$submenu_file"
        echo "    :sc::text = '${select_index}s' as show_${custom_link_name}_${select_index}," >> "$submenu_file"
        echo "    :sc::text = '${select_index}e' as edit_${custom_link_name}_${select_index}," >> "$submenu_file"
        select_index=$((select_index + 1))
    done
    
    echo "    :sc::text = 'b' as do_back_to_main," >> "$submenu_file"
    echo "    :sc::text = 'q' as do_quit" >> "$submenu_file"
    echo "\gset" >> "$submenu_file"
    echo "" >> "$submenu_file"
    echo "\if :do_quit" >> "$submenu_file"
    echo "    \echo 'Bye!'" >> "$submenu_file"
    echo "    \echo" >> "$submenu_file"
    echo "\elif :do_back_to_main" >> "$submenu_file"
    echo "    \i ${MENU_SCRIPT}" >> "$submenu_file"
    
    # Generate execution branches for each menu option
    local branch_index=1
    for sql_file in "${sql_files[@]}"; do
        local escaped_sql_file=$(echo "$sql_file" | sed 's/\\/\\\\/g')
        
        # Regular execution
        echo "\elif :do_${custom_link_name}_${branch_index}" >> "$submenu_file"
        echo "    \i ${escaped_sql_file}" >> "$submenu_file"
        echo "    \prompt 'Press <Enter> to continue ...' do_dummy" >> "$submenu_file"
        echo "    \i ${submenu_file}" >> "$submenu_file"
        
        # Show path
        echo "\elif :show_${custom_link_name}_${branch_index}" >> "$submenu_file"
        echo "    \echo 'Script path: ${escaped_sql_file}'" >> "$submenu_file"
        echo "    \prompt 'Press <Enter> to continue ...' do_dummy" >> "$submenu_file"
        echo "    \i ${submenu_file}" >> "$submenu_file"
        
        # Edit with backup
        echo "\elif :edit_${custom_link_name}_${branch_index}" >> "$submenu_file"
        echo "    \\! cp ${escaped_sql_file} ${escaped_sql_file}.bkp_\\\$(date +%Y%m%d_%H%M%S)" >> "$submenu_file"
        echo "    \\! view ${escaped_sql_file}" >> "$submenu_file"
        echo "    \prompt 'Press <Enter> to continue ...' do_dummy" >> "$submenu_file"
        echo "    \i ${submenu_file}" >> "$submenu_file"
        
        branch_index=$((branch_index + 1))
    done
    
    echo "\else" >> "$submenu_file"
    echo "    \echo" >> "$submenu_file"
    echo "    \echo 'ERROR: Unknown option! Try again.'" >> "$submenu_file"
    echo "    \echo" >> "$submenu_file"
    echo "    \i ${submenu_file}" >> "$submenu_file"
    echo "\endif" >> "$submenu_file"
}

# Clean up old custom submenu files
cleanup_custom_submenus() {
    if [[ -d "$CUSTOM_DIR" ]]; then
        while IFS= read -r submenu; do
            rm -f "$submenu"
        done < <(find "$CUSTOM_DIR" -maxdepth 1 -type f -name "sub_menu__*.psql" 2>/dev/null || true)
    fi
}

##############################
## Main
##############################

# Check for scripts
if ! [[ -d ${SQL_DIR} ]]; then
    echo "ERROR: ${SQL_DIR} not found. Please clone latest version of repository using link below:"
    echo "${DBA_TOOLS_REPO}"
    exit 1
fi

# Backup current files if any
for file in "${MENU_SCRIPT}" "${PSQLRC_FILE}"; do
    if [[ -f "${file}" ]]; then
        mv "${file}" "${file}_$(date +%Y%m%d)T$(date +%H%M%S)"
    fi
done

# Update PSQLRC_FILE
echo "-- ${DBA_TOOLS}" >> ${PSQLRC_FILE}
echo "\set dba '\\\\i ${MENU_SCRIPT}'" >> ${PSQLRC_FILE}

# Update MENU_SCRIPT with version info banner
echo "\i ${SQL_DIR}/VERSION.sql" >> ${MENU_SCRIPT}
echo "\echo" >> ${MENU_SCRIPT}

# Prepare main menu
echo "\echo 'Menu:'" >> ${MENU_SCRIPT}

# Find regular directories with numeric prefix
dirs=($(find "${SQL_DIR}" -maxdepth 1 \( -type d -o -type l \) -name "[0-9]*_*" | sort -V))

# Process regular directories
for dir in "${dirs[@]}"; do
    # Skip if it's a symlink in custom directory (handled separately)
    if [[ "$dir" == "${CUSTOM_DIR}"* ]] && [[ -L "$dir" ]]; then
        continue
    fi
    
    dir_name=$(basename "$dir")
    prefix=${dir_name%%_*}
    name=${dir_name#*_}
    display_name=$(echo "$name" | sed 's/_/ /g')
    display_name=$(echo "$display_name" | sed 's/\b\(.\)/\u\1/g')
    
    # Add to main menu
    echo "\echo '  ${prefix} - ${display_name}'" >> ${MENU_SCRIPT}
    
    # Create submenu for this directory
    submenu_file="${dir}/sub_menu__${name}.psql"
    
    # Get SQL files in the directory, sorted by numeric prefix
    sql_files=($(find "${dir}" -maxdepth 1 -type f -name "[0-9]*_*.sql" | sort -V))
    
    # Skip if no SQL files found
    if [[ ${#sql_files[@]} -eq 0 ]]; then
        continue
    fi
    
    # Start building submenu
    echo "\\echo" > "${submenu_file}"
    echo "\\echo '===== ${display_name} ====='" >> "${submenu_file}"
    echo "\\echo" >> "${submenu_file}"
    echo "\\echo 'Menu:'" >> "${submenu_file}"
    
    # Add menu items for each SQL file
    for sql_file in "${sql_files[@]}"; do
        file_name=$(basename "$sql_file")
        file_prefix=$(echo "$file_name" | grep -o '^[0-9_]*[0-9]')
        
        # Read first line from SQL file and clean it
        if [[ -f "$sql_file" ]]; then
            description=$(head -n 1 "$sql_file" | sed 's/^[[:space:]]*--[[:space:]]*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            
            # If description is empty, use filename as fallback
            if [[ -z "$description" ]]; then
                description="${file_name%.sql}"
                description=$(echo "$description" | sed 's/^[0-9_]*_//' | sed 's/_/ /g')
            fi
        else
            description="${file_name%.sql}"
            description=$(echo "$description" | sed 's/^[0-9_]*_//' | sed 's/_/ /g')
        fi
        
        # Use just the second number from prefix
        menu_number=$(echo "$file_prefix" | awk -F'_' '{print $NF}')
        echo "\\echo '  ${menu_number} - ${description}'" >> "${submenu_file}"
    done
    
    echo "\\echo '  b - back to main menu'" >> "${submenu_file}"
    echo "\\echo '  q - quit'" >> "${submenu_file}"
    echo "\\echo" >> "${submenu_file}"
    echo "" >> "${submenu_file}"
    echo "\\prompt 'Type your choice and press <Enter>: ' sub_choice" >> "${submenu_file}"
    echo "\\set sc '\'' :sub_choice '\''" >> "${submenu_file}"
    echo "" >> ${submenu_file}
    echo "select" >> ${submenu_file}
    
    for sql_file in "${sql_files[@]}"; do
        file_name=$(basename "$sql_file")
        file_prefix=$(echo "$file_name" | grep -o '^[0-9_]*[0-9]')
        menu_number=$(echo "$file_prefix" | awk -F'_' '{print $NF}')
        echo "    :sc::text = '${menu_number}' as do_${menu_number}," >> ${submenu_file}
        echo "    :sc::text = '${menu_number}s' as show_${menu_number}," >> ${submenu_file}
        echo "    :sc::text = '${menu_number}e' as edit_${menu_number}," >> ${submenu_file}
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
        
        # Show path option
        echo "\elif :show_${menu_number}" >> ${submenu_file}
        echo "    \echo 'Script path: ${sql_file}'" >> ${submenu_file}
        echo "    \prompt 'Press <Enter> to continue ...' do_dummy" >> ${submenu_file}
        echo "    \i ${submenu_file}" >> ${submenu_file}
        
        # Edit with backup option
        echo "\elif :edit_${menu_number}" >> ${submenu_file}
        echo "    \\! cp ${sql_file} ${sql_file}.bkp_\\\$(date +%Y%m%d_%H%M%S)" >> ${submenu_file}
        echo "    \\! view ${sql_file}" >> ${submenu_file}
        echo "    \prompt 'Press <Enter> to continue ...' do_dummy" >> ${submenu_file}
        echo "    \i ${submenu_file}" >> ${submenu_file}
    done
    
    echo "\else" >> ${submenu_file}
    echo "    \echo" >> ${submenu_file}
    echo "    \echo 'ERROR: Unknown option! Try again.'" >> ${submenu_file}
    echo "    \echo" >> ${submenu_file}
    echo "    \i ${submenu_file}" >> ${submenu_file}
    echo "\endif" >> ${submenu_file}
done

# Add quit option to main menu
echo "\echo '  q - quit'" >> ${MENU_SCRIPT}
echo "\echo" >> ${MENU_SCRIPT}

# ===== CUSTOM SCRIPTS SUPPORT =====

# Create custom directory if it doesn't exist
if [[ ! -d "$CUSTOM_DIR" ]]; then
    mkdir -p "$CUSTOM_DIR"
    echo "Created custom scripts directory: $CUSTOM_DIR"
fi

# Clean up old custom submenu files
cleanup_custom_submenus

# Find all valid symlinks to directories in custom folder
custom_links=()
while IFS= read -r link; do
    if is_valid_symlink_to_dir "$link"; then
        custom_links+=("$link")
    else
        echo "Warning: $link is not a valid symlink to a directory. Skipping."
    fi
done < <(find "$CUSTOM_DIR" -maxdepth 1 -type l | sort -V)

# Add custom section to main menu if there are any valid links
# Custom section comes AFTER the quit option
if [[ ${#custom_links[@]} -gt 0 ]]; then
    #echo "\echo" >> ${MENU_SCRIPT}
    echo "\echo 'Custom scripts:'" >> ${MENU_SCRIPT}
    
    custom_index=1
    for link in "${custom_links[@]}"; do
        link_name=$(basename "$link")
        echo "\echo '  c${custom_index} - ${link_name}'" >> ${MENU_SCRIPT}
        custom_index=$((custom_index + 1))
    done
fi

echo "\echo" >> ${MENU_SCRIPT}
echo "" >> ${MENU_SCRIPT}
echo "\prompt 'Type your choice and press <Enter>: ' user_choice" >> ${MENU_SCRIPT}
echo "\set uc '\'' :user_choice '\''" >> ${MENU_SCRIPT}
echo "" >> ${MENU_SCRIPT}
echo "select" >> ${MENU_SCRIPT}

# Add conditions for regular directories
for dir in "${dirs[@]}"; do
    dir_name=$(basename "$dir")
    prefix=${dir_name%%_*}
    echo "    :uc::text = '${prefix}' as do_${prefix}," >> ${MENU_SCRIPT}
done

# Quit condition (before custom)
echo "    :uc::text = 'q' as do_quit," >> ${MENU_SCRIPT}

# Add conditions for custom links (after quit)
if [[ ${#custom_links[@]} -gt 0 ]]; then
    custom_index=1
    for link in "${custom_links[@]}"; do
        echo "    :uc::text = 'c${custom_index}' as do_custom_${custom_index}," >> ${MENU_SCRIPT}
        custom_index=$((custom_index + 1))
    done
fi

# Remove trailing comma from last condition
sed -i '$ s/,$//' ${MENU_SCRIPT}

echo "\gset" >> ${MENU_SCRIPT}
echo "" >> ${MENU_SCRIPT}
echo "\if :do_quit" >> ${MENU_SCRIPT}
echo "    \echo 'Bye!'" >> ${MENU_SCRIPT}
echo "    \echo" >> ${MENU_SCRIPT}

# Add branches for regular directories
for dir in "${dirs[@]}"; do
    dir_name=$(basename "$dir")
    prefix=${dir_name%%_*}
    name=${dir_name#*_}
    submenu_file="${dir}/sub_menu__${name}.psql"
    echo "\elif :do_${prefix}" >> ${MENU_SCRIPT}
    echo "    \i ${submenu_file}"  >> ${MENU_SCRIPT}  
done

# Add branches for custom links
if [[ ${#custom_links[@]} -gt 0 ]]; then
    custom_index=1
    for link in "${custom_links[@]}"; do
        link_name=$(basename "$link")
        custom_submenu="${CUSTOM_DIR}/sub_menu__${link_name}.psql"
        
        # Generate submenu for this custom link
        generate_custom_submenu "$link"
        
        echo "\elif :do_custom_${custom_index}" >> ${MENU_SCRIPT}
        echo "    \i ${custom_submenu}" >> ${MENU_SCRIPT}
        custom_index=$((custom_index + 1))
    done
fi

echo "\else" >> ${MENU_SCRIPT}
echo "    \echo" >> ${MENU_SCRIPT}
echo "    \echo 'ERROR: Unknown option! Try again.'" >> ${MENU_SCRIPT}
echo "    \echo" >> ${MENU_SCRIPT}
echo "    \i ${MENU_SCRIPT}" >> ${MENU_SCRIPT}
echo "\endif" >> ${MENU_SCRIPT}

# Set permissions
chmod -R 700 ${SQL_DIR}/

echo "init.sh completed successfully"
echo "Custom scripts: place symlinks to your script directories in ${CUSTOM_DIR}"