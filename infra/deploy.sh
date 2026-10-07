#!/usr/bin/env bash
# Create (or update) everything on Azure with the Azure CLI. Safe to run again.
#
#   Resource group     rg-grid-carbon, resources in France Central
#   Azure SQL          a serverless database on the free offer: 100,000 vCore-seconds and 32 GB a
#                      month at no cost. When the month's allowance runs out it pauses until the
#                      next month instead of charging (--free-limit-exhaustion-behavior AutoPause).
#   Storage account    a public, read-only 'data' container the website reads its JSON from (CORS
#                      allows the portfolio's GitHub Pages origin), and the Function's own storage
#   Function App       Flex Consumption, Python 3.12, the timer in function_app/ (once a day);
#                      no Application Insights, whose log storage is the one part that could charge
#
# Needs `az login` first. Writes the connection settings to .env for the local commands.
#
#   infra/deploy.sh

set -euo pipefail
cd "$(dirname "$0")/.."

# France Central: free-trial subscriptions can't currently create SQL servers in UK South, UK
# West, North Europe or West Europe.
LOCATION=${LOCATION:-francecentral}
RG=${RG:-rg-grid-carbon}
SITE_ORIGIN=https://tristanbowdenfreeman-maker.github.io
SQL_ADMIN=gridadmin
DB=GridCarbon

# Azure names must be globally unique: add a short suffix derived from the subscription.
SUB=$(az account show --query id -o tsv)
SUFFIX=$(printf '%s' "$SUB" | shasum | cut -c1-6)
SQL_SERVER=sql-gridcarbon-$SUFFIX-$LOCATION
STORAGE=stgridcarbon$SUFFIX
FUNC=func-gridcarbon-$SUFFIX

# Keep the SQL password from an earlier run; otherwise make a strong one.
touch .env
SQL_PASSWORD=$(grep -E '^MSSQL_PASSWORD=.+' .env | cut -d= -f2- || true)
if [[ -z "$SQL_PASSWORD" ]]; then
  SQL_PASSWORD="Gc-$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-24)-9a"
fi

step() { printf '\n== %s\n' "$*"; }

step "Resource providers"
for ns in Microsoft.Sql Microsoft.Storage Microsoft.Web Microsoft.Insights Microsoft.OperationalInsights; do
  az provider register --namespace "$ns" --wait -o none
done

step "Resource group $RG ($LOCATION)"
az group show -n "$RG" -o none 2>/dev/null || az group create -n "$RG" -l "$LOCATION" -o none

step "Azure SQL server $SQL_SERVER"
if ! az sql server show -g "$RG" -n "$SQL_SERVER" -o none 2>/dev/null; then
  az sql server create -g "$RG" -n "$SQL_SERVER" -l "$LOCATION" \
    -u "$SQL_ADMIN" -p "$SQL_PASSWORD" --minimal-tls-version 1.2 -o none
fi
# Azure services (the Function App) and this machine may connect; nothing else.
az sql server firewall-rule create -g "$RG" -s "$SQL_SERVER" -n AllowAzureServices \
  --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 -o none
MY_IP=$(curl -s https://api.ipify.org)
az sql server firewall-rule create -g "$RG" -s "$SQL_SERVER" -n ThisMachine \
  --start-ip-address "$MY_IP" --end-ip-address "$MY_IP" -o none

step "Azure SQL database $DB (free offer, serverless)"
if ! az sql db show -g "$RG" -s "$SQL_SERVER" -n "$DB" -o none 2>/dev/null; then
  az sql db create -g "$RG" -s "$SQL_SERVER" -n "$DB" \
    -e GeneralPurpose -f Gen5 -c 2 --compute-model Serverless --min-capacity 0.5 \
    --use-free-limit true --free-limit-exhaustion-behavior AutoPause \
    --backup-storage-redundancy Local -o none
fi

step "Storage account $STORAGE"
if ! az storage account show -g "$RG" -n "$STORAGE" -o none 2>/dev/null; then
  az storage account create -g "$RG" -n "$STORAGE" -l "$LOCATION" --sku Standard_LRS --kind StorageV2 \
    --allow-blob-public-access true --min-tls-version TLS1_2 -o none
fi
STORAGE_CONN=$(az storage account show-connection-string -g "$RG" -n "$STORAGE" --query connectionString -o tsv)
az storage container create -n data --public-access blob --connection-string "$STORAGE_CONN" -o none
az storage cors clear --services b --connection-string "$STORAGE_CONN"
az storage cors add --services b --methods GET HEAD OPTIONS \
  --origins "$SITE_ORIGIN" http://localhost:8000 http://127.0.0.1:8000 http://localhost:8010 \
  --allowed-headers '*' --exposed-headers '*' --max-age 3600 --connection-string "$STORAGE_CONN"

step "Function App $FUNC (Flex Consumption, Python 3.12)"
if ! az functionapp show -g "$RG" -n "$FUNC" -o none 2>/dev/null; then
  az functionapp create -g "$RG" -n "$FUNC" --storage-account "$STORAGE" \
    --flexconsumption-location "$LOCATION" --runtime python --runtime-version 3.12 \
    --instance-memory 2048 --disable-app-insights true -o none
fi
az functionapp config appsettings set -g "$RG" -n "$FUNC" -o none --settings \
  MSSQL_HOST="$SQL_SERVER.database.windows.net" MSSQL_PORT=1433 MSSQL_USER="$SQL_ADMIN" \
  MSSQL_PASSWORD="$SQL_PASSWORD" MSSQL_DATABASE="$DB" \
  AZURE_STORAGE_CONNECTION_STRING="$STORAGE_CONN" AZURE_STORAGE_CONTAINER=data

step "Writing .env"
cat > .env <<ENV
MSSQL_HOST=$SQL_SERVER.database.windows.net
MSSQL_PORT=1433
MSSQL_USER=$SQL_ADMIN
MSSQL_PASSWORD=$SQL_PASSWORD
MSSQL_DATABASE=$DB
AZURE_STORAGE_CONNECTION_STRING=$STORAGE_CONN
AZURE_STORAGE_CONTAINER=data
AZURE_RESOURCE_GROUP=$RG
AZURE_FUNCTION_APP=$FUNC
ENV
chmod 600 .env

printf '\nDone. The site reads from https://%s.blob.core.windows.net/data/\n' "$STORAGE"
printf 'Next: python -m grid_carbon setup-db, then the backfill (README), then infra/publish_function.sh\n'
