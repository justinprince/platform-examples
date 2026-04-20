terraform {
  required_providers {
    azurerm    = { source = "hashicorp/azurerm" }
    chainguard = { source = "chainguard-dev/chainguard" }
    ko         = { source = "ko-build/ko" }
    null       = { source = "hashicorp/null" }
    random     = { source = "hashicorp/random" }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.sub_id

  # ── Azure Government (optional) ────────────────────────────────────────────
  # Uncomment to target Azure Government Cloud.
  #
  # environment     = "usgovernment"
}

provider "chainguard" {}

provider "ko" {}

data "azurerm_client_config" "current" {}
