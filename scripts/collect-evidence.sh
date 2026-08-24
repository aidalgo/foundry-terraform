#!/usr/bin/env bash
set -u

usage() {
  cat <<'EOF'
Usage:
  collect-evidence.sh --scenario-dir DIR --subscription ID --resource-group NAME \
    --account NAME --subnet-id ID [--apply-log FILE] [--operation-url URL]
EOF
}

scenario_dir=""
subscription_id=""
resource_group_name=""
account_name=""
subnet_id=""
apply_log=""
operation_url=""

while (($# > 0)); do
  case "$1" in
    --scenario-dir) scenario_dir="${2:-}"; shift 2 ;;
    --subscription) subscription_id="${2:-}"; shift 2 ;;
    --resource-group) resource_group_name="${2:-}"; shift 2 ;;
    --account) account_name="${2:-}"; shift 2 ;;
    --subnet-id) subnet_id="${2:-}"; shift 2 ;;
    --apply-log) apply_log="${2:-}"; shift 2 ;;
    --operation-url) operation_url="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for value in scenario_dir subscription_id resource_group_name account_name subnet_id; do
  [[ -n "${!value}" ]] || { echo "Missing required argument: $value" >&2; exit 2; }
done

for command_name in az terraform; do
  command -v "$command_name" >/dev/null || { echo "Missing required command: $command_name" >&2; exit 1; }
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scenario_name="$(basename "$scenario_dir")"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
evidence_dir="$repo_root/evidence/${scenario_name}-${timestamp}"
mkdir -p "$evidence_dir"

capture() {
  local output_file="$1"
  shift
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    "$@"
  } >"$evidence_dir/$output_file" 2>&1
  return 0
}

capture terraform-version.json terraform version -json
capture terraform-providers.txt terraform -chdir="$scenario_dir" providers
capture terraform-output.json terraform -chdir="$scenario_dir" output -json
capture azure-context.json az account show --query '{subscription:id,tenant:tenantId,cloud:environmentName,userType:user.type}' -o json
capture provider-registrations.json az provider list --query "[?namespace=='Microsoft.App' || namespace=='Microsoft.CognitiveServices' || namespace=='Microsoft.ContainerService' || namespace=='Microsoft.DocumentDB' || namespace=='Microsoft.MachineLearningServices' || namespace=='Microsoft.Network' || namespace=='Microsoft.Search' || namespace=='Microsoft.Storage'].{namespace:namespace,state:registrationState}" -o json
capture subnet.json az network vnet subnet show --ids "$subnet_id" -o json
capture activity-log.json az monitor activity-log list --subscription "$subscription_id" --resource-group "$resource_group_name" --offset 7d --max-events 500 -o json
capture deleted-accounts.json az cognitiveservices account list-deleted --query "[?name=='$account_name']" -o json

account_id="/subscriptions/$subscription_id/resourceGroups/$resource_group_name/providers/Microsoft.CognitiveServices/accounts/$account_name"
capture account.json az rest --method get --url "https://management.azure.com${account_id}?api-version=2026-03-01"
capture account-capability-hosts.json az rest --method get --url "https://management.azure.com${account_id}/capabilityHosts?api-version=2025-06-01"
capture projects.json az rest --method get --url "https://management.azure.com${account_id}/projects?api-version=2025-06-01"

project_id="$(terraform -chdir="$scenario_dir" output -raw project_id 2>/dev/null || true)"
if [[ -n "$project_id" && "$project_id" != "null" ]]; then
  capture project-capability-hosts.json az rest --method get --url "https://management.azure.com${project_id}/capabilityHosts?api-version=2025-06-01"
fi

if [[ -n "$operation_url" ]]; then
  capture operation-result.json az rest --method get --url "$operation_url"
fi

if [[ -n "$apply_log" && -f "$apply_log" ]]; then
  cp "$apply_log" "$evidence_dir/terraform-apply.log"
fi

cat >"$evidence_dir/README.txt" <<EOF
Collected at: $timestamp
Scenario: $scenario_name
Account: $account_name
Resource group: $resource_group_name

Commands may fail when the resource was never created. Each file includes the
command and its stderr so missing resources remain useful evidence.
EOF

echo "Evidence written to $evidence_dir"