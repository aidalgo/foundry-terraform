# Foundry VNet Injection Diagnostic Harness

This repository isolates Microsoft Foundry Agent Service VNet injection from the
larger Standard Agent setup. It provides two disposable, independent Terraform
scenarios:

| Scenario | Account implementation | Account API |
| --- | --- | --- |
| `azapi` | AzAPI `2.12.0` | `2025-06-01` by default; optional fresh-name `2026-03-01` control |
| `azurerm` | AzureRM `4.81.0` | `2026-03-01` inside the provider |

The first comparison is provider-plus-API-path parity, not a pure provider-only
test. AzureRM does not expose `useMicrosoftManagedNetwork` in HCL.

No live Azure deployment is run automatically. Every apply is an explicit
operator action and creates billable resources.

## What It Tests

Each scenario has its own state, account name, resource group, VNet, and dedicated
agent subnet. Never reuse one scenario's account name or subnet in the other.

1. `network` creates a clean `/23` VNet, dedicated `/24` agent subnet delegated
   only to `Microsoft.App/environments`, and a separate `/24` private endpoint
   subnet.
2. `account` adds one `AIServices` Foundry account with project management and
   VNet injection enabled. It creates no project, BYO data service, or explicit
   capability host.
3. `full` adds private Storage, Cosmos DB, and Standard AI Search, six private DNS
   zones, four private endpoints, a project, three AAD connections, RBAC, and the
   account/project `agents` capability hosts.

The `account` phase is the primary probe. If it fails with a capability-host or
virtual-workspace message, that work was initiated by the service rather than by
an explicit Terraform capability-host resource.

## Prerequisites

- Terraform `>= 1.11.4, < 2.0.0`.
- Azure CLI authenticated to the intended tenant and subscription.
- Permission to create resources and role assignments. Owner is simplest;
  Contributor plus Role Based Access Control Administrator is sufficient when
  correctly scoped.
- These resource providers registered: `Microsoft.App`,
  `Microsoft.CognitiveServices`, `Microsoft.ContainerService`,
  `Microsoft.DocumentDB`, `Microsoft.MachineLearningServices`,
  `Microsoft.Network`, `Microsoft.Search`, and `Microsoft.Storage`.
- A globally unique, never-before-used `run_id` for each attempt.

The full phase incurs costs for Standard AI Search, Cosmos DB, Storage, and
private endpoints. The network and account phases are the lower-cost diagnostic
path. Confirm current prices and organizational policy before applying.

Microsoft Learn references:

- [Foundry Agent Service virtual networks](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks)
- [Foundry Agent Service networking options](https://learn.microsoft.com/azure/foundry/agents/concepts/networking-options)
- [Recover or purge a deleted Azure AI services resource](https://learn.microsoft.com/azure/ai-services/recover-purge-resources)

## Prepare One Scenario

Start with `azapi`; run the AzureRM scenario only after preserving the first
result. The examples below assume the repository root as the current directory.

```bash
cp scenarios/azapi/terraform.tfvars.example scenarios/azapi/terraform.tfvars
```

Edit the copied file with the subscription ID, a unique `run_id`, and owner tag.
For `run_id = "a001"`, the expected account name is
`fndry-azapi-a001`. For AzureRM `run_id = "r001"`, it is
`fndry-azrm-r001`.

Run the non-mutating preflight before creating anything:

```bash
./scripts/preflight.sh \
  --subscription 00000000-0000-0000-0000-000000000000 \
  --account fndry-azapi-a001
```

Initialize the selected root:

```bash
terraform -chdir=scenarios/azapi init
terraform -chdir=scenarios/azapi validate
```

## Phase 1: Network

```bash
terraform -chdir=scenarios/azapi apply -var='test_phase=network'
```

Capture the subnet output and run preflight again. This pass asserts:

- `Succeeded` provisioning state.
- RFC1918 prefix of `/27` or larger; `/24` is the default.
- Exactly one `Microsoft.App/environments` delegation.
- No NSG, route table, NAT gateway, service endpoints, IP configurations, or
  service association links.
- No custom DNS servers on the diagnostic VNet.

```bash
AGENT_SUBNET_ID="$(terraform -chdir=scenarios/azapi output -raw agent_subnet_id)"

./scripts/preflight.sh \
  --subscription 00000000-0000-0000-0000-000000000000 \
  --account fndry-azapi-a001 \
  --subnet-id "$AGENT_SUBNET_ID"
```

Do not continue if the subnet is not pristine.

## Phase 2: Account Injection

Run this phase once for a given name and subnet. Capture UTC start/end times and
the complete apply output:

```bash
set -o pipefail
{
  date -u
  terraform -chdir=scenarios/azapi apply -var='test_phase=account'
  date -u
} 2>&1 | tee azapi-account-apply.log
```

Collect evidence whether the apply succeeds, fails, or reaches Terraform's
90-minute timeout:

```bash
./scripts/collect-evidence.sh \
  --scenario-dir "$PWD/scenarios/azapi" \
  --subscription 00000000-0000-0000-0000-000000000000 \
  --resource-group rg-fndry-azapi-a001 \
  --account fndry-azapi-a001 \
  --subnet-id "$AGENT_SUBNET_ID" \
  --apply-log azapi-account-apply.log
```

An ARM asynchronous-operation URL can also be captured with
`--operation-url URL`. Evidence is written under ignored `evidence/` and includes
the Terraform/provider versions, filtered Azure context, provider registrations,
Terraform outputs, raw account GET, capability-host/project list attempts,
expanded subnet state, deleted-account state, and seven days of Activity Log.
Failed reads are preserved with stderr because `404`, `Workspace not found`, and
similar responses are diagnostic evidence.

A Terraform timeout does not prove Azure cancelled the backend operation. Do not
rerun `apply`, reuse the account name, or reuse the subnet while the account is
`Creating` or `Failed`. Preserve evidence first.

## Run the A/B Control

After preserving the AzAPI result, repeat the same procedure from
`scenarios/azurerm` with a fresh `run_id`. Its default VNet is
`10.242.0.0/23`, distinct from AzAPI's `10.240.0.0/23`.

```bash
cp scenarios/azurerm/terraform.tfvars.example scenarios/azurerm/terraform.tfvars
terraform -chdir=scenarios/azurerm init
terraform -chdir=scenarios/azurerm validate
```

Run the scenarios sequentially. Never import or convert one account resource type
into the other scenario's state.

If AzAPI `2025-06-01` and AzureRM differ, use a third fresh account name, `run_id`,
and subnet with this AzAPI setting to isolate the API version:

```hcl
account_api_version = "2026-03-01"
```

## Phase 3: Full Standard Agent

Advance only a scenario whose account phase reached `Succeeded`:

```bash
terraform -chdir=scenarios/azapi apply -var='test_phase=full'
```

This diagnostic stage deliberately omits model deployments, Application
Insights/AMPLS, jump boxes, hub peering, custom DNS forwarders, NSGs, UDRs,
firewalls, CI, and remote state. Those variables can obscure the account-injection
result.

After success, confirm:

- All four private endpoint connections are approved.
- The Storage, Cosmos DB, Search, and Foundry public endpoints are disabled.
- All three project connections exist.
- Both `agents` capability hosts report `Succeeded`.

## Interpret Results

| Observation | Strongest next hypothesis |
| --- | --- |
| Both clean account paths fail and the subnet shows a foreign Microsoft subscription/resource with no expected SAL | Platform routing or regional backend state; open a support case with both evidence bundles. |
| AzureRM fails and AzAPI succeeds | Provider/API serialization path; run a fresh AzAPI `2026-03-01` control. |
| Both standalone paths succeed while the customer hub-spoke deployment fails | Landing-zone policy, DNS, peering, UDR/NSG, shared subnet, or stale-name difference. |
| Account succeeds and `full` fails | BYO connection, RBAC propagation, private endpoint, DNS, Search, Storage, or Cosmos issue. |
| East US 2 fails while a fresh supported-region control succeeds | Regional service or backend-state difference. |

## Cleanup

Always collect evidence before cleanup. Never manually delete
`legionservicelink`.

For a `full` run, remove downstream resources first:

```bash
terraform -chdir=scenarios/azapi apply -var='test_phase=account'
```

This destroys the project capability host before the account capability host,
then removes the project and BYO resources. Next remove the account while keeping
the network available for inspection:

```bash
terraform -chdir=scenarios/azapi apply -var='test_phase=network'
```

The AzureRM provider is configured to purge soft-deleted cognitive accounts. For
an AzAPI-created account, purge it explicitly after deletion:

```bash
az cognitiveservices account purge \
  --name fndry-azapi-a001 \
  --resource-group rg-fndry-azapi-a001 \
  --location eastus2
```

Poll both conditions before destroying the VNet:

```bash
az cognitiveservices account list-deleted \
  --query "[?name=='fndry-azapi-a001'].id" -o tsv

az network vnet subnet show --ids "$AGENT_SUBNET_ID" \
  --query 'serviceAssociationLinks[].id' -o tsv
```

Both commands must return empty output. Backend unlinking can take approximately
20 minutes. If either remains or deletion reports an active backend operation,
stop, preserve evidence, and do not destroy or reuse the network.

Only then remove the network phase:

```bash
terraform -chdir=scenarios/azapi destroy
```
