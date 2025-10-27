#!/bin/bash
# Example script for migrating Kavita from SQLite to PostgreSQL
# This is a REFERENCE IMPLEMENTATION - customize for your needs!
#
# Prerequisites:
#   - PostgreSQL installed and running
#   - pgloader installed (https://pgloader.io/)
#   - Kavita stopped during migration

set -e

# Configuration
SQLITE_DB="config/kavita.db"
PG_HOST="localhost"
PG_PORT="5432"
PG_DATABASE="kavita"
PG_USER="kavita"
PG_PASSWORD="your_password"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Kavita SQLite to PostgreSQL Migration Script${NC}"
echo "============================================="
echo ""

# Step 1: Verify prerequisites
echo -e "${YELLOW}[1/7] Verifying prerequisites...${NC}"

if [ ! -f "$SQLITE_DB" ]; then
    echo -e "${RED}Error: SQLite database not found at $SQLITE_DB${NC}"
    exit 1
fi

if ! command -v pgloader &> /dev/null; then
    echo -e "${RED}Error: pgloader is not installed${NC}"
    echo "Install with: sudo apt install pgloader (Debian/Ubuntu)"
    echo "            : brew install pgloader (macOS)"
    exit 1
fi

if ! command -v psql &> /dev/null; then
    echo -e "${RED}Error: PostgreSQL client (psql) is not installed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites verified${NC}"

# Step 2: Backup SQLite database
echo -e "${YELLOW}[2/7] Backing up SQLite database...${NC}"
BACKUP_FILE="${SQLITE_DB}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$SQLITE_DB" "$BACKUP_FILE"
echo -e "${GREEN}✓ Backup created: $BACKUP_FILE${NC}"

# Step 3: Create PostgreSQL database
echo -e "${YELLOW}[3/7] Creating PostgreSQL database...${NC}"
PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d postgres << EOF
-- Drop database if exists (BE CAREFUL!)
-- DROP DATABASE IF EXISTS $PG_DATABASE;

-- Create database
CREATE DATABASE $PG_DATABASE OWNER $PG_USER;
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ PostgreSQL database created${NC}"
else
    echo -e "${RED}Error creating PostgreSQL database${NC}"
    exit 1
fi

# Step 4: Create pgloader configuration
echo -e "${YELLOW}[4/7] Creating pgloader configuration...${NC}"
PGLOADER_CONF="pgloader-kavita.load"

cat > "$PGLOADER_CONF" << EOF
LOAD DATABASE
     FROM sqlite://$SQLITE_DB
     INTO postgresql://$PG_USER:$PG_PASSWORD@$PG_HOST:$PG_PORT/$PG_DATABASE

WITH include drop, create tables, create indexes, reset sequences

SET work_mem to '16MB', maintenance_work_mem to '512 MB';

CAST type datetime to timestamptz drop default drop not null using zero-dates-to-null,
     type date drop not null drop default using zero-dates-to-null;
EOF

echo -e "${GREEN}✓ pgloader configuration created${NC}"

# Step 5: Run migration
echo -e "${YELLOW}[5/7] Running pgloader migration (this may take a while)...${NC}"
pgloader "$PGLOADER_CONF"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Data migration completed${NC}"
else
    echo -e "${RED}Error during migration${NC}"
    exit 1
fi

# Step 6: Verify migration
echo -e "${YELLOW}[6/7] Verifying migration...${NC}"
SQLITE_COUNT=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM Series;")
PG_COUNT=$(PGPASSWORD="$PG_PASSWORD" psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" -t -c "SELECT COUNT(*) FROM \"Series\";")

echo "Series count in SQLite: $SQLITE_COUNT"
echo "Series count in PostgreSQL: $PG_COUNT"

if [ "$SQLITE_COUNT" -eq "$PG_COUNT" ]; then
    echo -e "${GREEN}✓ Verification passed${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Record counts don't match. Please verify manually.${NC}"
fi

# Step 7: Update configuration
echo -e "${YELLOW}[7/7] Update Kavita configuration...${NC}"
echo ""
echo "To complete the migration, update your config/appsettings.json:"
echo ""
echo '{'
echo '  "DatabaseSettings": {'
echo '    "Provider": "PostgreSQL",'
echo "    \"ConnectionString\": \"Host=$PG_HOST;Port=$PG_PORT;Database=$PG_DATABASE;Username=$PG_USER;Password=$PG_PASSWORD\""
echo '  }'
echo '}'
echo ""
echo -e "${GREEN}Migration complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Update your config/appsettings.json with the settings above"
echo "2. Start Kavita and verify everything works"
echo "3. If successful, you can remove the SQLite backup: $BACKUP_FILE"
echo ""
echo -e "${YELLOW}Keep the SQLite backup until you're sure everything is working!${NC}"

# Cleanup
rm -f "$PGLOADER_CONF"

