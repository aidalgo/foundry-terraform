# Foundry VNet Injection Test

Use this repository to test Microsoft Foundry Agent Service VNet injection.
The repository contains two independent Terraform scenarios.
Each scenario creates disposable Azure resources.

| Scenario | Account implementation | Account API |
| --- | --- | --- |
| `azapi` | AzAPI `2.12.0` | `2025-06-01` by default. You can also select `2026-03-01`. |
| `azurerm` | AzureRM `4.81.0` | The provider uses `2026-03-01`. |

The first test compares both the provider and the API path.
It is not a provider-only test.
AzureRM does not expose `useMicrosoftManagedNetwork` in HCL.

Terraform does not deploy Azure resources automatically.
You must run each `terraform apply` command.
An apply creates resources that can cause costs.

## Test Scope

Each scenario uses a separate state, account name, resource group, VNet, and agent subnet.
Do not use an account name or subnet in both scenarios.

1. The `network` phase creates a clean `/23` VNet.
  It creates a dedicated `/24` agent subnet.
  This subnet has only the `Microsoft.App/environments` delegation.
  The phase also creates a separate `/24` private endpoint subnet.
2. The `account` phase creates one `AIServices` Foundry account.
  It enables project management and VNet injection.
  It does not create a project, a BYO data service, or an explicit capability host.
3. The `full` phase creates the remaining Standard Agent resources.
  These resources include Storage, Cosmos DB, Standard AI Search, and six private DNS zones.
  This phase also creates four private endpoints, one project, three AAD connections, and RBAC assignments.
  It creates the account and project `agents` capability hosts.

Use the `account` phase as the primary test.
A capability-host or virtual-workspace error can occur during this phase.
In this case, the Foundry service started that operation.
Terraform did not create an explicit capability-host resource.

## Repository Layout

Each scenario has one Terraform source file:

| Path | Purpose |
| --- | --- |
| `scenarios/azapi/main.tf` | Defines the AzAPI scenario. |
| `scenarios/azurerm/main.tf` | Defines the AzureRM scenario. |
| `modules/` | Contains the shared network, account, and Standard Agent modules. |
| `scripts/preflight.sh` | Checks the subscription, account name, and agent subnet. |
| `scripts/collect-evidence.sh` | Collects Terraform and Azure evidence. |

Each scenario `main.tf` contains provider requirements, input variables, modules, and outputs.
Commit each `.terraform.lock.hcl` file to source control.
Do not commit state files, local `terraform.tfvars` files, logs, or evidence files.

## Prerequisites

Before you start, complete these steps:

- Install Terraform `>= 1.11.4, < 2.0.0`.
- Install Azure CLI.
- Sign in to the correct Azure tenant and subscription.
- Make sure that your identity can create resources and role assignments.
- Use Owner, or use Contributor with Role Based Access Control Administrator.
- Register `Microsoft.App`.
- Register `Microsoft.CognitiveServices`.
- Register `Microsoft.ContainerService`.
- Register `Microsoft.DocumentDB`.
- Register `Microsoft.MachineLearningServices`.
- Register `Microsoft.Network`.
- Register `Microsoft.Search`.
- Register `Microsoft.Storage`.
- Create a new `run_id` for each test attempt.

The `run_id` must be globally unique and must not have been used before.

The `full` phase creates resources that cause costs.
These resources include Standard AI Search, Cosmos DB, Storage, and private endpoints.
Use the `network` and `account` phases for the lower-cost diagnostic test.
Before an apply, check current prices and your organization policies.

Microsoft Learn references:

- [Foundry Agent Service virtual networks](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks)
- [Foundry Agent Service networking options](https://learn.microsoft.com/azure/foundry/agents/concepts/networking-options)
- [Recover or purge a deleted Azure AI services resource](https://learn.microsoft.com/azure/ai-services/recover-purge-resources)

## Prepare the AzAPI Scenario

Start with the `azapi` scenario.
Keep its result before you start the AzureRM scenario.
Run all commands from the repository root.

Create the local variable file:

```bash
cp scenarios/azapi/terraform.tfvars.example scenarios/azapi/terraform.tfvars
```

Open `scenarios/azapi/terraform.tfvars`.
Set the subscription ID, a new `run_id`, and the owner tag.

For `run_id = "a001"`, the account name is `fndry-azapi-a001`.
For AzureRM `run_id = "r001"`, the account name is `fndry-azrm-r001`.

Run the preflight check before you create resources.
This command does not change Azure resources.

```bash
./scripts/preflight.sh \
  --subscription 00000000-0000-0000-0000-000000000000 \
  --account fndry-azapi-a001
```

Initialize and validate the AzAPI scenario:

```bash
terraform -chdir=scenarios/azapi init
terraform -chdir=scenarios/azapi validate
```

## Phase 1: Create the Network

Create the network resources:

```bash
terraform -chdir=scenarios/azapi apply -var='test_phase=network'
```

Get the agent subnet ID:

```bash
AGENT_SUBNET_ID="$(terraform -chdir=scenarios/azapi output -raw agent_subnet_id)"
```

Run the preflight check again:

```bash
./scripts/preflight.sh \
  --subscription 00000000-0000-0000-0000-000000000000 \
  --account fndry-azapi-a001 \
  --subnet-id "$AGENT_SUBNET_ID"
```

The second preflight check makes sure that these conditions are true:

- The subnet provisioning state is `Succeeded`.
- The subnet has an RFC1918 prefix of `/27` or larger.
- The subnet has one `Microsoft.App/environments` delegation.
- The subnet has no NSG, route table, or NAT gateway.
- The subnet has no service endpoints or IP configurations.
- The subnet has no service association links.
- The diagnostic VNet has no custom DNS servers.

Do not continue if the subnet check fails.

## Phase 2: Create the Account

Use each account name and subnet for only one account-phase attempt.
Record the UTC start time, end time, and full command output.

```bash
set -o pipefail
{
  date -u
  terraform -chdir=scenarios/azapi apply -var='test_phase=account'
  date -u
} 2>&1 | tee azapi-account-apply.log
```

Run the evidence script after the apply command stops.
Run it after a success, a failure, or a Terraform timeout.

```bash
./scripts/collect-evidence.sh \
  --scenario-dir "$PWD/scenarios/azapi" \
  --subscription 00000000-0000-0000-0000-000000000000 \
  --resource-group rg-fndry-azapi-a001 \
  --account fndry-azapi-a001 \
  --subnet-id "$AGENT_SUBNET_ID" \
  --apply-log azapi-account-apply.log
```

To collect an ARM asynchronous-operation result, add `--operation-url URL`.

The script writes the files to the ignored `evidence/` directory.
The files contain this information:

- Terraform and provider versions.
- A filtered Azure context.
- Resource provider registrations.
- Terraform outputs.
- The raw account response.
- Capability-host and project list responses.
- The full subnet state.
- The deleted-account state.
- Seven days of Azure Activity Log events.

Some read operations can fail when a resource does not exist.
The script stores standard error with each failed read.
Errors such as `404` and `Workspace not found` are useful evidence.

A Terraform timeout does not mean that Azure stopped the backend operation.
Do not run `apply` again while the account state is `Creating` or `Failed`.
Do not use the account name or subnet again.
Collect and keep the evidence first.

## Run the AzureRM Control

Collect and keep the AzAPI result before you run the AzureRM control.
Use a new `run_id`.
The AzureRM VNet uses `10.242.0.0/23` by default.
The AzAPI VNet uses `10.240.0.0/23` by default.

Create the local variable file, initialize the scenario, and validate it:

```bash
cp scenarios/azurerm/terraform.tfvars.example scenarios/azurerm/terraform.tfvars
terraform -chdir=scenarios/azurerm init
terraform -chdir=scenarios/azurerm validate
```

Repeat phases 1 and 2 with these AzureRM values:

| AzAPI value | AzureRM value |
| --- | --- |
| `scenarios/azapi` | `scenarios/azurerm` |
| `fndry-azapi-a001` | `fndry-azrm-r001` |
| `rg-fndry-azapi-a001` | `rg-fndry-azrm-r001` |
| `AGENT_SUBNET_ID` | `AZRM_AGENT_SUBNET_ID` |
| `azapi-account-apply.log` | `azurerm-account-apply.log` |

Run the two scenarios one at a time.
Do not import an account from one scenario into the other scenario state.
Do not convert an account resource type in an existing state.

If the two results differ, test the API version as a separate control.
Use a new AzAPI account name, `run_id`, and subnet.
Set this value in the new AzAPI `terraform.tfvars` file:

```hcl
account_api_version = "2026-03-01"
```

## Phase 3: Create the Full Standard Agent

Start this phase only after the account provisioning state is `Succeeded`.

```bash
terraform -chdir=scenarios/azapi apply -var='test_phase=full'
```

This test does not include these optional components:

- Model deployments.
- Application Insights or AMPLS.
- Jump boxes.
- Hub peering.
- Custom DNS forwarders.
- NSGs, UDRs, or firewalls.
- CI or remote state.

These components can change the account-injection result.

After the apply succeeds, make sure that these conditions are true:

- Azure approves all four private endpoint connections.
- Public network access is off for Storage, Cosmos DB, Search, and Foundry.
- All three project connections exist.
- Both `agents` capability hosts have the `Succeeded` state.

## Interpret the Results

| Observation | Next action |
| --- | --- |
| Both clean account tests fail. The subnet has an unexpected Microsoft resource and no expected SAL. | Check for a platform routing or regional backend problem. Open a support case with both evidence sets. |
| AzureRM fails and AzAPI succeeds. | Run a new AzAPI `2026-03-01` control. Check the provider and API serialization path. |
| Both standalone tests succeed, but the hub-and-spoke deployment fails. | Check policy, DNS, peering, UDRs, NSGs, shared subnets, and old account names. |
| The account phase succeeds and the `full` phase fails. | Check BYO connections, RBAC, private endpoints, DNS, Search, Storage, and Cosmos DB. |
| East US 2 fails and a new test in another supported region succeeds. | Check for a regional service or backend problem. |

## Cleanup

Collect and keep the evidence before cleanup.
Do not manually delete `legionservicelink`.

For a `full` run, first return to the account phase:

```bash
terraform -chdir=scenarios/azapi apply -var='test_phase=account'
```

Terraform removes the project capability host before the account capability host.
It then removes the project and BYO resources.

Next, return to the network phase:

```bash
terraform -chdir=scenarios/azapi apply -var='test_phase=network'
```

This command removes the account and keeps the network for inspection.

The AzureRM provider purges soft-deleted cognitive accounts.
For an AzAPI account, purge the account after deletion:

```bash
az cognitiveservices account purge \
  --name fndry-azapi-a001 \
  --resource-group rg-fndry-azapi-a001 \
  --location eastus2
```

Run these commands until both commands return no output:

```bash
az cognitiveservices account list-deleted \
  --query "[?name=='fndry-azapi-a001'].id" -o tsv

az network vnet subnet show --ids "$AGENT_SUBNET_ID" \
  --query 'serviceAssociationLinks[].id' -o tsv
```

Azure can take approximately 20 minutes to remove backend links.
Stop if either command returns a value.
Also stop if Azure reports an active backend operation.
Keep the evidence, and do not delete or use the network again.

Destroy the network only after both commands return no output:

```bash
terraform -chdir=scenarios/azapi destroy
```

For the AzureRM scenario, replace `scenarios/azapi` with `scenarios/azurerm`.
