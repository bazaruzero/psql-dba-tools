# psql-dba-tools
Useful scripts for PostgreSQL DBA

## Installation

```bash
git clone https://github.com/bazaruzero/psql-dba-tools.git
cd ~/psql-dba-tools
./init.sh
echo "export PSQLRC=${HOME}/psql-dba-tools/psqlrc" >> ~/.bashrc && source ~/.bashrc
psql
```

## Usage
```
psql=> :dba
```
**Navigation:**  
`<number>` - enter menu / run script  
`b` - back to main menu  
`q` - quit

**Additional options in submenus:**  
`<number>p` - shows script path

`<number>o` - opens script in read-only mode

`<number>e` - opens script for edit

## Custom scripts

You can add your own scripts without modifying the repository:
1. Create symlinks to your script directories in `sql/custom/`:
    ```bash
    cd ~/psql-dba-tools/sql/custom
    ln -s /path/to/your/scripts my_scripts
    ```

2. Run `./init.sh` again
3. Custom sections appear after main menu as `c1 - my_scripts`

All scripts from linked directories appear in submenus with original filenames.
Options `s` and `e` work as for built-in scripts.

---
Inspired by [Nikolay Samokhvalov (postgres_dba)](https://github.com/NikolayS/postgres_dba) repo.
