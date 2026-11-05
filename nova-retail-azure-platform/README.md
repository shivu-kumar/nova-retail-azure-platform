# Nova Retail Azure Data Platform

Learning project: building an Azure data and analytics platform for a fictional Indian retailer, **Nova Retail**, one project at a time.

Dataset: 6 CSV files (star schema): FactSales (12,500 rows), DimCustomer, DimProduct, DimStore, DimSalesperson, DimDate.

## Project 1: Secure data lake foundation

### 1A. Portal build

| Resource | Name | Region |
|---|---|---|
| Resource group | rg-novaretail-dev | (fill in) |
| Storage account (ADLS Gen2) | (fill in) | (fill in) |
| Key Vault | (fill in) | (fill in) |
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

2. **What does the hierarchical namespace give me that plain Blob Storage does not?**

   Answer:

3. **Why is storage account key access disabled, and what replaces it?**

   Answer:

4. **What is the difference between soft delete and purge protection on Key Vault?**

   Answer:

### Control plane vs. data plane (one paragraph)

(Write this yourself. Mention Owner/Contributor vs. Storage Blob Data roles, and why the separation exists.)

### Data observations (from profiling the files)

- No nulls or duplicate rows; all foreign keys in FactSales match their dimensions.
- OrderID prefix (e.g. ORD2023...) does not always match the order year, so the ID must not be used as a date.
- About 3,300 orders are dated before the customer's CustomerSince date: a data quality rule to enforce in the silver layer (Project 3).
