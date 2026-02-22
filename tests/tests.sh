#!/bin/bash
# Test suite

set -e

##############################
## Config
##############################

# Name
DBA_TOOLS="psql-dba-tools"

# Paths
DBA_TOOLS_HOME="${HOME}/${DBA_TOOLS}"
SQL_DIR="${DBA_TOOLS_HOME}/sql"
MENU_SCRIPT="${DBA_TOOLS_HOME}/dba.psql"
PSQLRC_FILE="${DBA_TOOLS_HOME}/psqlrc"

# Database
#PSQL_CONN_STRING=""
TEST_DB="postgres"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # no color

# Counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0


##############################
## Helper Functions
##############################

#####
assert() {
    local test_name="$1"
    local condition="$2"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if eval "$condition" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Test ${TESTS_TOTAL}:${NC} $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}❌ Test ${TESTS_TOTAL}:${NC} $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

##############################
## Main
##############################

## Tests
echo ""
echo "===== Tests ====="

assert "psql is available" "command -v psql > /dev/null"
assert "SQL directory exists" "[[ -d '$SQL_DIR' ]]"
assert "SQL directory has subdirectories" "[[ -n \$(find '$SQL_DIR' -maxdepth 1 -type d -name '[0-9]*_*' 2>/dev/null) ]]"

assert "init.sh exists" "[[ -f '${DBA_TOOLS_HOME}/init.sh' ]]"

if [[ -f "${DBA_TOOLS_HOME}/init.sh" ]]; then
    set +e
    bash "${DBA_TOOLS_HOME}/init.sh" > /dev/null 2>&1
    init_status=$?
    set -e
    assert "init.sh executed successfully" "[[ ${init_status} -eq 0 ]]"
else
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}❌ Test ${TESTS_TOTAL}:${NC} init.sh executed successfully"
fi

assert "${MENU_SCRIPT} was created" "[[ -f '${MENU_SCRIPT}' ]]"
assert "${PSQLRC_FILE} was created" "[[ -f '${PSQLRC_FILE}' ]]"
assert "${PSQLRC_FILE} contains dba shortcut" "grep -q '\\\\set dba' '${PSQLRC_FILE}'"
assert "${SQL_DIR}/VERSION.sql exists" "[[ -f '${SQL_DIR}/VERSION.sql' ]]"
assert "${MENU_SCRIPT} contains VERSION include" "grep -q 'VERSION.sql' '${MENU_SCRIPT}'"

## Summary
echo ""
echo "===== Summary ====="
echo "Total:        $TESTS_TOTAL"
echo -e "${GREEN}Passed:       $TESTS_PASSED${NC}"
echo -e "${RED}Failed:       $TESTS_FAILED${NC}"
