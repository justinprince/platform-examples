# Chainguard Image Copy — Azure Deployment

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fjustinprince%2Fplatform-examples%2Fmain%2Fimage-copy-acr-blueprint%2Finfra%2Fazuredeploy.json)

[![Deploy to Azure Government](https://aka.ms/deploytoazuregovbutton)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fjustinprince%2Fplatform-examples%2Fmain%2Fimage-copy-acr-blueprint%2Finfra%2Fazuredeploy.json)

Deploys the full Azure infrastructure to build and run `cgr-image-copy:v1` from your repository's Dockerfile, with Chainguard OIDC authentication via Azure Key Vault. The ACR image build is **triggered automatically** during deployment — no manual build step required.

---

## Resources Deployed

| Resource | Description |
|---|---|
| **Azure Container Registry (ACR)** | Stores the built container image |
| **ACR Task** | Builds `cgr-image-copy:v1` from the Dockerfile in this repo |
| **Deployment Script (AzureCLI)** | Automatically runs `az acr task run` during deployment and waits for success |
| **Script Runner Identity** | Dedicated managed identity scoped to ACR Contributor, used only by the deployment script |
| **Azure Key Vault** | Holds the `chainguard-oidc-token` secret — created as a placeholder, updated manually post-deploy |
| **App Managed Identity** | Grants the Container App permission to pull from ACR and read the Key Vault secret |
| **Container App Environment** | Managed environment for the Container App |
| **Azure Container App** | Runs the container; starts only after the build script confirms the image exists |
| **Log Analytics Workspace** | Captures Container App logs |

---

## Deployment Order (enforced by dependsOn)

```
Log Analytics → ACR + Key Vault + Managed Identities
     ↓
Role Assignments (ACR Pull, KV Secrets User, ACR Contributor for script)
     ↓
ACR Task (definition)
     ↓
Deployment Script  ← triggers az acr task run, polls to completion
     ↓
Container App  ← guaranteed the image exists before first pull
```

---

## Using the Deploy to Azure Button

Clicking the button above opens the Azure Portal custom deployment UI pre-loaded with this template. The portal will prompt you for:

| Parameter | Required | Default |
|---|---|---|
| `containerRegistryName` | **Yes** | _(none — must be globally unique)_ |
| `location` | No | Resource group location |
| `keyVaultName` | No | `kv-cgr-<uniqueSuffix>` |
| `containerAppName` | No | `cgr-image-copy-app` |
| `containerAppEnvironmentName` | No | `cgr-container-env` |
| `gitRepoUrl` | No | `https://github.com/justinprince/platform-examples` |
| `gitRepoBranch` | No | `main` |
| `dockerfilePath` | No | `image-copy-acr-blueprint/infra/Dockerfile` |
| `gitRepoContextPath` | No | `image-copy-acr-blueprint/infra` |

The only value you **must** provide is a unique ACR name. All other parameters have sensible defaults pointing at this repo.

> **Permissions note:** The account deploying the template must have permission to create role assignments on the resource group (Owner or User Access Administrator).

---

## CLI Deployment (alternative)

```bash
az group create --name <your-resource-group> --location eastus

az deployment group create \
  --resource-group <your-resource-group> \
  --template-file azuredeploy.json \
  --parameters @azuredeploy.parameters.json \
  --parameters containerRegistryName=<your-unique-acr-name>
```

Deployment takes 10–20 minutes depending on Docker build time.

---

## Post-Deployment: Set the Chainguard OIDC Token

This is the **only remaining manual step**. The Key Vault secret is created as a placeholder during deployment. Update it with your real token (the exact command is in the deployment outputs as `updateSecretCommand`):

```bash
az keyvault secret set \
  --vault-name <key-vault-name> \
  --name chainguard-oidc-token \
  --value "YOUR_ACTUAL_CHAINGUARD_OIDC_TOKEN"
```

Then restart the Container App to pick up the new value:

```bash
az containerapp revision restart \
  --resource-group <your-resource-group> \
  --name cgr-image-copy-app \
  --revision $(az containerapp revision list \
    --resource-group <your-resource-group> \
    --name cgr-image-copy-app \
    --query '[0].name' -o tsv)
```

---

## How the Token is Mounted

The secret is pulled live from Key Vault by the Container App's managed identity and injected into the container as:

```
CHAINGUARD_OIDC_TOKEN=<value>
```

---

## Private Repo Note

This repo is public, so ACR Tasks can clone it natively. If you fork this into a private repo, add a PAT credential to the ACR Task after deployment:

```bash
az acr task credential add \
  --registry <acr-name> \
  --name build-cgr-image-copy \
  --login-server github.com \
  --username YOUR_GITHUB_USERNAME \
  --password YOUR_PAT
```

---

## File Layout

```
platform-examples/
└── image-copy-acr-blueprint/
    └── infra/
        ├── Dockerfile
        ├── azuredeploy.json
        ├── azuredeploy.parameters.json
        └── README.md
```
