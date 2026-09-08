/* ============================================================
   INVENTORY & BILLING MANAGEMENT SYSTEM — VERSION 2 (ADVANCED)
   Database: Microsoft SQL Server (T-SQL)
   Features: Multi-item invoices, stock validation, InvoiceNumber,
             PaymentMethod, TotalAmount, Views, Indexes
   ============================================================ */

CREATE DATABASE InventoryBillingDB_V2;
GO
USE InventoryBillingDB_V2;
GO

-- ============================================================
-- STEP 1: TABLES
-- ============================================================

CREATE TABLE Products (
    ProductID   INT IDENTITY(1,1) PRIMARY KEY,
    ProductName VARCHAR(100) NOT NULL,
    Price       DECIMAL(10,2) NOT NULL CHECK (Price >= 0),
    StockQty    INT NOT NULL CHECK (StockQty >= 0)
);
GO

CREATE TABLE Customers (
    CustomerID   INT IDENTITY(1,1) PRIMARY KEY,
    CustomerName VARCHAR(100) NOT NULL,
    Phone        VARCHAR(15)
);
GO

CREATE TABLE Sales (
    SaleID        INT IDENTITY(1,1) PRIMARY KEY,
    InvoiceNumber VARCHAR(20) NULL,               -- filled after insert
    CustomerID    INT NOT NULL,
    SaleDate      DATETIME NOT NULL DEFAULT GETDATE(),
    PaymentMethod VARCHAR(20) NOT NULL
        CHECK (PaymentMethod IN ('Cash','Card','UPI','NetBanking')),
    TotalAmount   DECIMAL(12,2) NOT NULL DEFAULT 0,
    CONSTRAINT FK_Sales_Customers FOREIGN KEY (CustomerID)
        REFERENCES Customers(CustomerID)
);
GO

CREATE TABLE SaleDetails (
    SaleDetailID INT IDENTITY(1,1) PRIMARY KEY,
    SaleID       INT NOT NULL,
    ProductID    INT NOT NULL,
    Quantity     INT NOT NULL CHECK (Quantity > 0),
    UnitPrice    DECIMAL(10,2) NOT NULL,          -- price locked at sale time
    CONSTRAINT FK_SaleDetails_Sales FOREIGN KEY (SaleID)
        REFERENCES Sales(SaleID),
    CONSTRAINT FK_SaleDetails_Products FOREIGN KEY (ProductID)
        REFERENCES Products(ProductID)
);
GO

-- ============================================================
-- STEP 2: INDEXES  (performance — talking point in interview)
-- ============================================================

CREATE UNIQUE INDEX UQ_Sales_InvoiceNumber ON Sales(InvoiceNumber)
    WHERE InvoiceNumber IS NOT NULL;               -- filtered unique index
CREATE INDEX IX_Sales_CustomerID   ON Sales(CustomerID);
CREATE INDEX IX_Sales_SaleDate     ON Sales(SaleDate);
CREATE INDEX IX_SaleDetails_SaleID    ON SaleDetails(SaleID);
CREATE INDEX IX_SaleDetails_ProductID ON SaleDetails(ProductID);
GO
-- Why: CustomerID/ProductID/SaleID are used in every JOIN and report
-- query above — indexing FK columns speeds up joins and lookups
-- without slowing down inserts much, since this table is read-heavy.

-- ============================================================
-- STEP 3: TABLE TYPE — for multi-product invoices in one call
-- ============================================================

CREATE TYPE SaleItemType AS TABLE (
    ProductID INT,
    Quantity  INT
);
GO

-- ============================================================
-- STEP 4: SAMPLE MASTER DATA
-- ============================================================

INSERT INTO Products (ProductName, Price, StockQty) VALUES
('Wireless Mouse', 450.00, 60),
('Keyboard', 800.00, 40),
('USB Pen Drive 32GB', 350.00, 120),
('HDMI Cable', 250.00, 25),
('Laptop Stand', 900.00, 30),
('Webcam HD', 1200.00, 15),
('Bluetooth Speaker', 1500.00, 12);
GO

INSERT INTO Customers (CustomerName, Phone) VALUES
('Rahul Sharma', '9800011122'),
('Priya Das', '9830022233'),
('Amit Roy', '9876543210'),
('Sneha Ghosh', '9123456789'),
('Debjit Sen', '9445566778'),
('Ananya Basu', '9051122334');
GO

-- ============================================================
-- STEP 5: STORED PROCEDURE — Create a multi-item invoice
--          with STOCK VALIDATION before committing
-- ============================================================

CREATE PROCEDURE sp_CreateInvoice
    @CustomerID    INT,
    @PaymentMethod VARCHAR(20),
    @Items         SaleItemType READONLY,
    @NewSaleID     INT OUTPUT,
    @InvoiceNumber VARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1) Validate stock for every item BEFORE inserting anything
        IF EXISTS (
            SELECT 1
            FROM @Items I
            INNER JOIN Products P ON P.ProductID = I.ProductID
            WHERE I.Quantity > P.StockQty
        )
        BEGIN
            THROW 51000, 'Insufficient stock for one or more products.', 1;
        END

        -- 2) Create the invoice header
        INSERT INTO Sales (CustomerID, SaleDate, PaymentMethod, TotalAmount)
        VALUES (@CustomerID, GETDATE(), @PaymentMethod, 0);

        SET @NewSaleID = SCOPE_IDENTITY();
        SET @InvoiceNumber = 'INV-' + FORMAT(@NewSaleID, '000000');

        -- 3) Insert all line items, locking in current price
        INSERT INTO SaleDetails (SaleID, ProductID, Quantity, UnitPrice)
        SELECT @NewSaleID, I.ProductID, I.Quantity, P.Price
        FROM @Items I
        INNER JOIN Products P ON P.ProductID = I.ProductID;

        -- 4) Deduct stock for every item
        UPDATE P
        SET P.StockQty = P.StockQty - I.Quantity
        FROM Products P
        INNER JOIN @Items I ON P.ProductID = I.ProductID;

        -- 5) Calculate and store TotalAmount + InvoiceNumber
        UPDATE Sales
        SET TotalAmount = (
                SELECT SUM(Quantity * UnitPrice)
                FROM SaleDetails
                WHERE SaleID = @NewSaleID
            ),
            InvoiceNumber = @InvoiceNumber
        WHERE SaleID = @NewSaleID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- ============================================================
-- STEP 6: REALISTIC SALES DATA (multiple products per invoice)
-- ============================================================

DECLARE @SaleID INT, @InvNo VARCHAR(20);
DECLARE @Items1 SaleItemType, @Items2 SaleItemType, @Items3 SaleItemType,
        @Items4 SaleItemType, @Items5 SaleItemType;

-- Invoice 1: Rahul buys Mouse + Keyboard
INSERT INTO @Items1 VALUES (1, 2), (2, 1);
EXEC sp_CreateInvoice @CustomerID=1, @PaymentMethod='UPI',
     @Items=@Items1, @NewSaleID=@SaleID OUTPUT, @InvoiceNumber=@InvNo OUTPUT;

-- Invoice 2: Priya buys Pen Drive x5
INSERT INTO @Items2 VALUES (3, 5);
EXEC sp_CreateInvoice @CustomerID=2, @PaymentMethod='Cash',
     @Items=@Items2, @NewSaleID=@SaleID OUTPUT, @InvoiceNumber=@InvNo OUTPUT;

-- Invoice 3: Amit buys HDMI Cable + Laptop Stand + Webcam
INSERT INTO @Items3 VALUES (4, 2), (5, 1), (6, 1);
EXEC sp_CreateInvoice @CustomerID=3, @PaymentMethod='Card',
     @Items=@Items3, @NewSaleID=@SaleID OUTPUT, @InvoiceNumber=@InvNo OUTPUT;

-- Invoice 4: Sneha buys Bluetooth Speaker + Mouse
INSERT INTO @Items4 VALUES (7, 1), (1, 1);
EXEC sp_CreateInvoice @CustomerID=4, @PaymentMethod='NetBanking',
     @Items=@Items4, @NewSaleID=@SaleID OUTPUT, @InvoiceNumber=@InvNo OUTPUT;

-- Invoice 5: Debjit buys Keyboard + Pen Drive + HDMI Cable
INSERT INTO @Items5 VALUES (2, 2), (3, 3), (4, 4);
EXEC sp_CreateInvoice @CustomerID=5, @PaymentMethod='UPI',
     @Items=@Items5, @NewSaleID=@SaleID OUTPUT, @InvoiceNumber=@InvNo OUTPUT;
GO

-- Try this one to SEE the stock validation reject an over-sell:
-- DECLARE @BadItems SaleItemType, @S INT, @I VARCHAR(20);
-- INSERT INTO @BadItems VALUES (6, 999);  -- only 15 webcams in stock
-- EXEC sp_CreateInvoice @CustomerID=1, @PaymentMethod='Cash',
--      @Items=@BadItems, @NewSaleID=@S OUTPUT, @InvoiceNumber=@I OUTPUT;
-- Expect: Msg 51000 'Insufficient stock for one or more products.'

-- ============================================================
-- STEP 7: VIEWS
-- ============================================================

-- 7a. Invoice-level summary (header info, one row per invoice)
CREATE VIEW vw_InvoiceSummary AS
SELECT
    S.SaleID,
    S.InvoiceNumber,
    C.CustomerName,
    S.SaleDate,
    S.PaymentMethod,
    S.TotalAmount
FROM Sales S
INNER JOIN Customers C ON S.CustomerID = C.CustomerID;
GO

-- 7b. Line-item level detail (every product on every invoice)
CREATE VIEW vw_InvoiceDetails AS
SELECT
    S.InvoiceNumber,
    C.CustomerName,
    P.ProductName,
    SD.Quantity,
    SD.UnitPrice,
    (SD.Quantity * SD.UnitPrice) AS LineTotal,
    S.SaleDate,
    S.PaymentMethod
FROM SaleDetails SD
INNER JOIN Sales S ON SD.SaleID = S.SaleID
INNER JOIN Customers C ON S.CustomerID = C.CustomerID
INNER JOIN Products P ON SD.ProductID = P.ProductID;
GO

-- 7c. Low stock products
CREATE VIEW vw_LowStockProducts AS
SELECT ProductID, ProductName, StockQty
FROM Products
WHERE StockQty < 10;
GO

-- 7d. Customer spend ranking (window function — advanced!)
CREATE VIEW vw_CustomerSpendRanking AS
SELECT
    C.CustomerName,
    SUM(S.TotalAmount) AS TotalSpent,
    RANK() OVER (ORDER BY SUM(S.TotalAmount) DESC) AS SpendRank
FROM Sales S
INNER JOIN Customers C ON S.CustomerID = C.CustomerID
GROUP BY C.CustomerName;
GO

-- 7e. Best-selling products (window function)
CREATE VIEW vw_BestSellingProducts AS
SELECT
    P.ProductName,
    SUM(SD.Quantity) AS TotalUnitsSold,
    RANK() OVER (ORDER BY SUM(SD.Quantity) DESC) AS SalesRank
FROM SaleDetails SD
INNER JOIN Products P ON SD.ProductID = P.ProductID
GROUP BY P.ProductName;
GO

-- ============================================================
-- STEP 8: TEST QUERIES — run these to demo the whole system
-- ============================================================

SELECT * FROM vw_InvoiceSummary ORDER BY SaleID;
SELECT * FROM vw_InvoiceDetails ORDER BY InvoiceNumber;
SELECT * FROM vw_LowStockProducts;
SELECT * FROM vw_CustomerSpendRanking;
SELECT * FROM vw_BestSellingProducts;
SELECT * FROM Products;   -- confirm stock deducted correctly
GO
