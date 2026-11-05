# Nova Retail Azure Data Platform

Learning project: building an Azure data and analytics platform for a fictional Indian retailer, **Nova Retail**, one project at a time.

Dataset: 6 CSV files (star schema): FactSales (12,500 rows), DimCustomer, DimProduct, DimStore, DimSalesperson, DimDate.

## Project 1: Secure data lake foundation

### 1A. Portal build

| Resource | Name | Region |
|---|---|---|
| Resource group | rg-novaretail-dev | central india |
| Storage account (ADLS Gen2) | stnovaretaildev | central india |
| Key Vault | kv-novaretail-dev | central india |
| Budget | budget-novaretail | n/a |

Tags: environment=dev, project=p1-nova-retail, domain=retail-analytics, owner=(your name)

### Settings chosen and why

| Setting | Value | Why |
|---|---|---|
| Hierarchical namespace | On | Makes the account ADLS Gen2: real directories, folder-level ACLs, fast renames for Spark. Cannot be changed later. |
| Redundancy | LRS | Cheapest; fine for a lab. Prod would use ZRS or GRS (decide in Project 7). |
| Minimum TLS | 1.2 | Rejects older, weaker protocol versions. |
| Anonymous access | Off | No container can ever be made publicly readable by mistake. |
| Storage account key access | Off | (write in your own words; see "Key questions" below) |
| Key Vault permission model | Azure RBAC | One permission model for everything, with per-identity audit trail, instead of vault access policies. |
| Key Vault soft delete | 7 days | (write why it exists) |
| Key Vault purge protection | Off (lab only) | Lets me recreate the vault name after teardown. Would be On in prod. |
| Public network access | On (for now) | Locked down in Part 1C. |

### Bronze folder layout

Current (one-time load of 6 files):

```
bronze/
  nova_retail/
    DimCustomer.csv
    DimDate.csv
    DimProduct.csv
    DimSalesperson.csv
    DimStore.csv
    FactSales.csv
```

Decision: flat folder for the initial one-time load. A partitioned layout
(`nova_retail/<table>/ingest_date=YYYY-MM-DD/`) will be introduced when recurring
ingestion starts in Project 2, because that is when keeping every load matters.

### Key questions (answer in your own words)

1. **Why could I not read data in the lake as subscription Owner, until I assigned a role?**
   (Control plane vs. data plane. Include the two error messages you saw and what fixed each.)

   Answer:
   
  Azure separates the control plane from the data plane. The control plane covers managing the storage account itself (creating, deleting, modifying it), and Owner is a control-plane role. The data plane covers working with the data inside the account (reading, writing, modifying files), and it needs separate roles such as Storage Blob Data Contributor. I disabled storage account key access, so the portal could no longer use an access key to browse the container, and I got an error saying key-based authentication isn’t permitted. After I switched the authentication method to Microsoft Entra user account and held the Storage Blob Data Contributor role, I could list and upload files. Owner alone was not enough for the data, because only a data-plane role gives permission to read or write it.
   

2. **What does the hierarchical namespace give me that plain Blob Storage does not?**

   Answer:
   
   Plain Blob Storage has a flat namespace, so folders are only a naming convention inside blob names. With the hierarchical namespace enabled (ADLS Gen2), the account has real directories. That gives me three things: renaming or deleting a folder is a single atomic operation instead of copying or deleting every blob under that prefix, I can set folder-level permissions with POSIX-style ACLs on top of RBAC, and analytics engines such as Spark, Databricks and Fabric work faster and more reliably with it, using the dfs endpoint. This is why the lake for Nova Retail uses it: bronze, silver and gold are real folders I can secure and reorganize cleanly.

3. **Why is storage account key access disabled, and what replaces it?**

   Answer:
   An account key gives full, unrestricted access to everything in the storage account and bypasses RBAC entirely. It isn’t tied to any identity, so I can’t audit who used it, I can’t limit it to one container or to read-only, and it can leak through connection strings and code. I disabled key access so every request must authenticate with Microsoft Entra ID, using a user, managed identity or service principal, with access granted through RBAC roles such as Storage Blob Data Contributor. That gives per-identity audit trails, least privilege, and no secrets to rotate. Key Vault is still used, but for other secrets (passwords, API keys, certificates), not for storage access. The trade-off is that older tools that depend on account keys won’t work, so I’d check for those before disabling keys on an existing production account.

4. **What is the difference between soft delete and purge protection on Key Vault?**

   Answer:
	| Soft delete |	Purge protection
Purpose |	Recover from accidental deletion	Stop permanent deletion | during the retention period
Delete action	| Item enters a recoverable deleted state	| Blocks the purge action
During the retention period	| You can recover or purge it	| You can recover it, but nobody can purge it
Can it be turned off? |	Cannot be disabled on new vaults	| Once on, cannot be turned off

### Data observations (from profiling the files)

- No nulls or duplicate rows; all foreign keys in FactSales match their dimensions.
- OrderID prefix (e.g. ORD2023...) does not always match the order year, so the ID must not be used as a date.
- About 3,300 orders are dated before the customer's CustomerSince date: a data quality rule to enforce in the silver layer (Project 3).
