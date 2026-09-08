# Inventory & Billing Management System (SQL Server)

A mini ERP-style inventory and billing system built in Microsoft SQL Server (T-SQL), designed to demonstrate real-world database design and business logic — stock validation, multi-item invoicing, and reporting.

## Tech Stack
- Microsoft SQL Server
- T-SQL (Transact-SQL)
- SSMS (SQL Server Management Studio)

## Database Structure
- **Products** — product catalog with price and stock quantity
- **Customers** — customer records
- **Sales** — invoice header (invoice number, payment method, total amount, date)
- **SaleDetails** — invoice line items, linking Sales to Products (supports multiple products per invoice)

## Key Features
- **Multi-item invoices** — one invoice can include multiple products, inserted in a single stored procedure call using a table-valued parameter
- **Stock validation** — prevents overselling; if requested quantity exceeds available stock, the transaction is rolled back with a custom error
- **Transactional integrity** — invoice creation uses `BEGIN TRANSACTION` / `COMMIT` / `ROLLBACK` with `TRY...CATCH` error handling
- **Auto-generated InvoiceNumber and TotalAmount**
- **5 SQL Views** for reporting, including two using the `RANK()` window function:
  - `vw_InvoiceSummary`
  - `vw_InvoiceDetails`
  - `vw_LowStockProducts`
  - `vw_CustomerSpendRanking`
  - `vw_BestSellingProducts`
- **Indexes** on foreign key columns and a filtered unique index on `InvoiceNumber` for query performance

## How to Run
1. Open the `.sql` file in SQL Server Management Studio (SSMS)
2. Select all (Ctrl+A) and execute (F5) — this creates the database, tables, procedures, sample data, and views
3. Run the queries in the final section to view reports

## ER Diagram
See `er-diagram.png` in this repo.
