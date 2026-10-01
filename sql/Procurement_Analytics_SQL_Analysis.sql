/*
============================================================
PROJECT: Procurement Spend & Supplier Performance Analytics
DATABASE: ProcurementAnalytics
TOOLS: SQL Server, Power BI

PURPOSE:
Analyze procurement spending, supplier performance,
contract utilization, and purchase price variance (PPV)
to identify sourcing and supplier management opportunities.

KEY ANALYSIS AREAS:
1. Procurement Spend Analysis
2. Department and Category Spend
3. Supplier Spend Analysis
4. Supplier Delivery Performance
5. Supplier Quality Performance
6. Contract Utilization
7. Purchase Price Variance (PPV)
============================================================
*/

USE ProcurementAnalytics;
GO

/* ============================================================
   SECTION 1: DATA VALIDATION & QUALITY CHECKS
   ============================================================ */

-- 1.1 Review the number of records in each table
SELECT 'Suppliers' AS TableName, COUNT(*) AS RecordCount FROM Suppliers
UNION ALL
SELECT 'Departments', COUNT(*) FROM Departments
UNION ALL
SELECT 'Products', COUNT(*) FROM Products
UNION ALL
SELECT 'Contracts', COUNT(*) FROM Contracts
UNION ALL
SELECT 'PurchaseOrders', COUNT(*) FROM PurchaseOrders
UNION ALL
SELECT 'PurchaseOrderItems', COUNT(*) FROM PurchaseOrderItems
UNION ALL
SELECT 'Invoices', COUNT(*) FROM Invoices
UNION ALL
SELECT 'Budgets', COUNT(*) FROM Budgets;


-- 1.2 Check the purchase order date range
SELECT
    MIN(OrderDate) AS EarliestOrderDate,
    MAX(OrderDate) AS LatestOrderDate
FROM PurchaseOrders;


-- 1.3 Check for duplicate purchase order numbers
SELECT
    PONumber,
    COUNT(*) AS DuplicateCount
FROM PurchaseOrders
GROUP BY PONumber
HAVING COUNT(*) > 1;


-- 1.4 Check for purchase orders with missing key information
SELECT
    COUNT(*) AS MissingKeyFields
FROM PurchaseOrders
WHERE PONumber IS NULL
   OR SupplierID IS NULL
   OR DepartmentID IS NULL
   OR OrderDate IS NULL
   OR POValueUSD IS NULL;


-- 1.5 Validate total procurement spend
SELECT
    COUNT(DISTINCT PONumber) AS TotalPurchaseOrders,
    SUM(POValueUSD) AS TotalProcurementSpend,
    AVG(POValueUSD) AS AveragePOValue
FROM PurchaseOrders;

/* ============================================================
   SECTION 2: PROCUREMENT SPEND ANALYSIS
   ============================================================ */

-- 2.1 Annual procurement spend
SELECT
    YEAR(OrderDate) AS OrderYear,
    COUNT(DISTINCT PONumber) AS TotalPurchaseOrders,
    SUM(POValueUSD) AS TotalProcurementSpend
FROM PurchaseOrders
GROUP BY YEAR(OrderDate)
ORDER BY OrderYear;


-- 2.2 Top 10 departments by procurement spend
SELECT TOP 10
    d.DepartmentName,
    SUM(po.POValueUSD) AS TotalProcurementSpend
FROM PurchaseOrders po
JOIN Departments d
    ON po.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentName
ORDER BY TotalProcurementSpend DESC;


-- 2.3 Top 10 suppliers by procurement spend
SELECT TOP 10
    s.SupplierName,
    SUM(po.POValueUSD) AS TotalProcurementSpend
FROM PurchaseOrders po
JOIN Suppliers s
    ON po.SupplierID = s.SupplierID
GROUP BY s.SupplierName
ORDER BY TotalProcurementSpend DESC;


-- 2.4 Top 10 procurement categories by spend
SELECT TOP 10
    p.Category,
    SUM(poi.LineTotalUSD) AS TotalCategorySpend
FROM PurchaseOrderItems poi
JOIN Products p
    ON poi.ProductID = p.ProductID
GROUP BY p.Category
ORDER BY TotalCategorySpend DESC;

/* ============================================================
   SECTION 3: SUPPLIER PERFORMANCE ANALYSIS
   ============================================================ */

-- 3.1 Supplier on-time delivery performance
SELECT
    s.SupplierName,
    COUNT(*) AS TotalDeliveries,
    SUM(CASE
        WHEN po.AnalysisDeliveryStatus = 'On Time' THEN 1
        ELSE 0
    END) AS OnTimeDeliveries,
    CAST(
        100.0 * SUM(CASE
            WHEN po.AnalysisDeliveryStatus = 'On Time' THEN 1
            ELSE 0
        END)
        /
        NULLIF(SUM(CASE
            WHEN po.AnalysisDeliveryStatus IN ('On Time', 'Late') THEN 1
            ELSE 0
        END), 0)
        AS DECIMAL(10,2)
    ) AS OnTimeDeliveryRate
FROM PurchaseOrders po
JOIN Suppliers s
    ON po.SupplierID = s.SupplierID
GROUP BY s.SupplierName
ORDER BY OnTimeDeliveryRate ASC;


-- 3.2 Supplier quality acceptance performance
SELECT
    s.SupplierName,
    COUNT(*) AS TotalLineItems,
    SUM(CASE
        WHEN poi.QualityStatus = 'Accepted' THEN 1
        ELSE 0
    END) AS AcceptedItems,
    CAST(
        100.0 * SUM(CASE
            WHEN poi.QualityStatus = 'Accepted' THEN 1
            ELSE 0
        END)
        / NULLIF(COUNT(*), 0)
        AS DECIMAL(10,2)
    ) AS QualityAcceptanceRate
FROM PurchaseOrderItems poi
JOIN PurchaseOrders po
    ON poi.PONumber = po.PONumber
JOIN Suppliers s
    ON po.SupplierID = s.SupplierID
GROUP BY s.SupplierName
ORDER BY QualityAcceptanceRate ASC;

-- 3.3 Combined supplier performance scorecard
SELECT
    s.SupplierName,

    -- Procurement spend
    SUM(poi.LineTotalUSD) AS ProcurementSpend,

    -- On-time delivery rate
    CAST(
        100.0 *
        COUNT(DISTINCT CASE
            WHEN po.AnalysisDeliveryStatus = 'On Time'
            THEN po.PONumber
        END)
        /
        NULLIF(
            COUNT(DISTINCT CASE
                WHEN po.AnalysisDeliveryStatus IN ('On Time', 'Late')
                THEN po.PONumber
            END),
            0
        )
        AS DECIMAL(10,2)
    ) AS OnTimeDeliveryRate,

    -- Quality acceptance rate
    CAST(
        100.0 *
        SUM(CASE
            WHEN poi.QualityStatus = 'Accepted' THEN 1
            ELSE 0
        END)
        /
        NULLIF(COUNT(*), 0)
        AS DECIMAL(10,2)
    ) AS QualityAcceptanceRate,

    -- Supplier rating
    MAX(s.SupplierRating) AS SupplierRating,

    -- Average purchase price variance
    CAST(
        AVG(poi.PurchasePriceVariancePct)
        AS DECIMAL(10,2)
    ) AS AveragePPV

FROM Suppliers s
JOIN PurchaseOrders po
    ON s.SupplierID = po.SupplierID
JOIN PurchaseOrderItems poi
    ON po.PONumber = poi.PONumber

GROUP BY
    s.SupplierName

ORDER BY
    ProcurementSpend DESC;

/* ============================================================
   SECTION 4: CONTRACT UTILIZATION & PPV ANALYSIS
   ============================================================ */

-- 4.1 Overall contracted spend rate
SELECT
    SUM(LineTotalUSD) AS TotalSpend,

    SUM(
        CASE
            WHEN ContractedPurchase = 'Yes'
            THEN LineTotalUSD
            ELSE 0
        END
    ) AS ContractedSpend,

    SUM(
        CASE
            WHEN ContractedPurchase <> 'Yes'
                 OR ContractedPurchase IS NULL
            THEN LineTotalUSD
            ELSE 0
        END
    ) AS NonContractedSpend,

    CAST(
        100.0 *
        SUM(
            CASE
                WHEN ContractedPurchase = 'Yes'
                THEN LineTotalUSD
                ELSE 0
            END
        )
        / NULLIF(SUM(LineTotalUSD), 0)
        AS DECIMAL(10,2)
    ) AS ContractedSpendRate

FROM PurchaseOrderItems;


-- 4.2 Average PPV by contract status
SELECT
    CASE
        WHEN ContractedPurchase = 'Yes'
            THEN 'Contracted'
        ELSE 'Non-Contracted'
    END AS ContractStatus,

    CAST(
        AVG(PurchasePriceVariancePct)
        AS DECIMAL(10,2)
    ) AS AveragePPV

FROM PurchaseOrderItems

GROUP BY
    CASE
        WHEN ContractedPurchase = 'Yes'
            THEN 'Contracted'
        ELSE 'Non-Contracted'
    END

ORDER BY ContractStatus;

-- 4.3 Top 10 categories by non-contracted spend
SELECT TOP 10
    p.Category,

    SUM(
        CASE
            WHEN poi.ContractedPurchase <> 'Yes'
                 OR poi.ContractedPurchase IS NULL
            THEN poi.LineTotalUSD
            ELSE 0
        END
    ) AS NonContractedSpend

FROM PurchaseOrderItems poi
JOIN Products p
    ON poi.ProductID = p.ProductID

GROUP BY p.Category

ORDER BY NonContractedSpend DESC;


-- 4.4 Contract coverage rate by category
SELECT
    p.Category,

    SUM(poi.LineTotalUSD) AS TotalCategorySpend,

    SUM(
        CASE
            WHEN poi.ContractedPurchase = 'Yes'
            THEN poi.LineTotalUSD
            ELSE 0
        END
    ) AS ContractedSpend,

    CAST(
        100.0 *
        SUM(
            CASE
                WHEN poi.ContractedPurchase = 'Yes'
                THEN poi.LineTotalUSD
                ELSE 0
            END
        )
        / NULLIF(SUM(poi.LineTotalUSD), 0)
        AS DECIMAL(10,2)
    ) AS ContractCoverageRate

FROM PurchaseOrderItems poi
JOIN Products p
    ON poi.ProductID = p.ProductID

GROUP BY p.Category

ORDER BY ContractCoverageRate ASC;


-- 4.5 Categories with highest unfavorable average PPV
SELECT TOP 10
    p.Category,

    CAST(
        AVG(poi.PurchasePriceVariancePct)
        AS DECIMAL(10,2)
    ) AS AveragePPV

FROM PurchaseOrderItems poi
JOIN Products p
    ON poi.ProductID = p.ProductID

GROUP BY p.Category

ORDER BY AveragePPV DESC;

/* ============================================================
   SECTION 5: MANAGEMENT OPPORTUNITY SUMMARY
   ============================================================ */

-- 5.1 Identify high-spend suppliers with performance concerns
WITH SupplierPerformance AS
(
    SELECT
        s.SupplierName,

        SUM(poi.LineTotalUSD) AS ProcurementSpend,

        100.0 *
        COUNT(DISTINCT CASE
            WHEN po.AnalysisDeliveryStatus = 'On Time'
            THEN po.PONumber
        END)
        /
        NULLIF(
            COUNT(DISTINCT CASE
                WHEN po.AnalysisDeliveryStatus IN ('On Time', 'Late')
                THEN po.PONumber
            END),
            0
        ) AS OnTimeDeliveryRate,

        100.0 *
        SUM(CASE
            WHEN poi.QualityStatus = 'Accepted' THEN 1
            ELSE 0
        END)
        /
        NULLIF(COUNT(*), 0) AS QualityAcceptanceRate,

        AVG(poi.PurchasePriceVariancePct) AS AveragePPV

    FROM Suppliers s

    JOIN PurchaseOrders po
        ON s.SupplierID = po.SupplierID

    JOIN PurchaseOrderItems poi
        ON po.PONumber = poi.PONumber

    GROUP BY
        s.SupplierName
)

SELECT
    SupplierName,
    CAST(ProcurementSpend AS DECIMAL(18,2)) AS ProcurementSpend,
    CAST(OnTimeDeliveryRate AS DECIMAL(10,2)) AS OnTimeDeliveryRate,
    CAST(QualityAcceptanceRate AS DECIMAL(10,2)) AS QualityAcceptanceRate,
    CAST(AveragePPV AS DECIMAL(10,2)) AS AveragePPV,

    CASE
        WHEN OnTimeDeliveryRate < 50
          OR QualityAcceptanceRate < 85
          OR AveragePPV > 2
        THEN 'Performance Review'
        ELSE 'Monitor'
    END AS ManagementAction

FROM SupplierPerformance

WHERE ProcurementSpend >= 30000000

ORDER BY ProcurementSpend DESC;