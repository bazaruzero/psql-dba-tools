# psql-dba-tools
Useful scripts for PostgreSQL DBA

# Installation

```bash
git clone https://github.com/bazaruzero/psql-dba-tools.git
cd ~/psql-dba-tools
./init.sh
echo "export PSQLRC=${HOME}/psql-dba-tools/psqlrc" >> ~/.bashrc && source ~/.bashrc
psql
psql=> :dba
```

Inspired by [Nikolay Samokhvalov (postgres_dba)](https://github.com/NikolayS/postgres_dba) repo.
