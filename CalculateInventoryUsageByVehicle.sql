USE [YourDatabaseName]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/*
    Stored Procedure: [dbo].[CalculateInventoryUsageByVehicle]
    Description: This stored procedure calculates and updates the inventory usage by vehicle. It processes vehicle inventory data, 
    considering any inventory movements, and updates the related tables to reflect accurate inventory levels.
    
    Author: Adeola Idowu
    Created On: CURRENT_TIMESTAMP -- This automatically uses the current system date and time
    Last Modified: CURRENT_TIMESTAMP -- This automatically uses the current system date and time
*/

ALTER PROC [dbo].[CalculateInventoryUsageByVehicle]
    (@rundate DATE = NULL,          -- The starting date for the calculation
     @daystoCalculate INT = 0,      -- The number of days to calculate inventory for
     @SpotsMoved INT                -- Flag to indicate if spots have been moved (0 = no, 1 = yes)
    ) 
AS
BEGIN
    -- Declare local variables to be used throughout the procedure
    DECLARE @tryDate DATE, @tryStartTime TIME, @CompanyTypeID INT, @orderSpotID INT, @schedulerID INT,
            @PackageVehicleID INT, @schedulerOrderSpotID INT, @packageVehicleSpotMultiplier INT,
            @packageVehicleStartTime TIME, @packageVehicleEndTime TIME, 
            @packageVehicleStartDate DATE, @packageVehicleEndDate DATE,
            @packageVehicleMonday BIT, @packageVehicleTuesday BIT, @packageVehicleWednesday BIT, 
            @OrderDetailWeekID INT, @packageVehicleThursday BIT, @packageVehicleFriday BIT, 
            @packageVehicleSaturday BIT, @packageVehicleSunday BIT, 
            @programVehicleMonday BIT, @programVehicleTuesday BIT, @programVehicleWednesday BIT, 
            @programVehicleThursday BIT, @programVehicleFriday BIT, @programVehicleSaturday BIT, 
            @programVehicleSunday BIT, @OrderStatusID INT, @OrderHeaderID INT, @NonSpot CHAR(1), 
            @programVehicleStartTime TIME, @programVehicleEndTime TIME, @vehicleID INT, 
            @firstLegacySellTime TIME, @legacySellTime TIME, @usage INT,
            @programVehicleSpotMultiplier INT, @programVehicleID INT, @programSpotTypeID INT,
            @SpotTypeID INT, @SpotLength INT, @WeekStartDate DATE, @SchedulerTypeID INT;

    -- Create a temporary table to store the calculated inventory usage data
    CREATE TABLE #InventoryUsageByVehicleForCursor 
    (
        OrderSpotID INT, PackageVehicleID INT, StartTime TIME(0), EndTime TIME(0), 
        Monday BIT, Tuesday BIT, Wednesday BIT, Thursday BIT, Friday BIT, 
        Saturday BIT, Sunday BIT, StartDate DATE, EndDate DATE, 
        SpotMultiplier INT, VehicleID INT, SpotTypeID INT, 
        SpotLength INT, WeekStartDate DATE, CompanyTypeID INT, 
        SchedulerTypeID INT, OrderStatusID INT, OrderDetailID INT, 
        NonSpot CHAR(1), OrderHeaderID INT, OrderDetailWeekID INT 
    );

    -- Create a temporary table to track inventory moves that have been processed
    CREATE TABLE #PackageVehicleMoveInventoryProcessed
    (
        PackageVehicleID INT, OrderDetailWeekID INT, OrderSpotID INT, 
        WeekStart DATE, Spots INT
    );

    -- Insert data into the temporary table from the inventory move table
    INSERT INTO #PackageVehicleMoveInventoryProcessed
    (PackageVehicleID, OrderDetailWeekID, OrderSpotID, WeekStart, Spots)
    SELECT SourcePackageVehicleID, SourceOrderDetailWeekID, SourceOrderSpotID, odw.StartDate, -pvm.Spots
    FROM dbo.PackageVehicleMove pvm
    INNER JOIN dbo.OrderDetailWeek odw ON pvm.SourceOrderDetailWeekID = odw.ID
    WHERE IsInventoryProcessed = 0
    UNION ALL
    SELECT TargetPackageVehicleID, TargetOrderDetailWeekID, TargetOrderSpotID, odw.StartDate, pvm.Spots
    FROM dbo.PackageVehicleMove pvm 
    LEFT JOIN dbo.OrderDetailWeek odw ON pvm.TargetOrderDetailWeekID = odw.ID
    WHERE IsInventoryProcessed = 0 AND TargetWeek IS NULL 
    UNION ALL
    SELECT TargetPackageVehicleID, TargetOrderDetailWeekID, TargetOrderSpotID, TargetWeek, pvm.Spots
    FROM dbo.PackageVehicleMove pvm 
    WHERE TargetWeek IS NOT NULL AND IsInventoryProcessed = 0;

    -- Insert data into the inventory usage table based on input parameters
    IF (@SpotsMoved = 0) -- Calculate inventory for all weeks
    BEGIN
        INSERT INTO #InventoryUsageByVehicleForCursor
        (OrderSpotID, PackageVehicleID, StartTime, EndTime, Monday, Tuesday, Wednesday, 
         Thursday, Friday, Saturday, Sunday, StartDate, EndDate, SpotMultiplier, VehicleID, 
         SpotTypeID, SpotLength, WeekStartDate, CompanyTypeID, SchedulerTypeID, 
         OrderStatusID, NonSpot, OrderHeaderID, OrderDetailWeekID)
        
        -- Select records for inventory usage calculation
        SELECT DISTINCT os.ID, pv.ID, pv.StartTime, pv.EndTime, pv.Monday, pv.Tuesday, 
               pv.Wednesday, pv.Thursday, pv.Friday, pv.Saturday, pv.Sunday, 
               pv.StartDate, ISNULL(pv.EndDate, '2050-01-01'), 
               pv.SpotMultiplier - ISNULL(pvms.SpotsMovedFrom, 0) + ISNULL(pvmt.SpotsMovedTo, 0), 
               pv.VehicleID, CASE WHEN st.IncludeInAvailsReport = 1 THEN NULL ELSE pv.SpotTypeID END, 
               od.Length, odw.StartDate, oh.CompanyTypeID, oh.SchedulerTypeID, 
               oh.OrderStatusID, od.NonSpot, od.OrderHeaderID, odw.ID
        FROM OrderHeader oh
        INNER JOIN OrderDetail od ON od.OrderHeaderID = oh.ID
        INNER JOIN OrderDetailWeek odw ON odw.OrderDetailID = od.ID
        INNER JOIN OrderSpot os ON os.OrderDetailWeekID = odw.ID
        INNER JOIN Package p ON p.ID = od.PackageID
        INNER JOIN PackageVehicle pv ON pv.PackageID = p.ID
        INNER JOIN Vehicle v ON v.ID = pv.VehicleID
        LEFT JOIN dbo.SpotType st ON st.ID = pv.SpotTypeID
        LEFT JOIN (
            -- Calculate spots moved from a package vehicle
            SELECT SourcePackageVehicleID, SourceOrderSpotID, SourceOrderDetailWeekID, 
                   SUM(Spots) AS SpotsMovedFrom
            FROM dbo.PackageVehicleMove
            WHERE SourceOrderSpotID IS NOT NULL AND SourcePackageVehicleID IS NOT NULL 
                  AND SourceOrderDetailWeekID IS NOT NULL
            GROUP BY SourcePackageVehicleID, SourceOrderSpotID, SourceOrderDetailWeekID
        ) pvms ON pvms.SourcePackageVehicleID = pv.ID 
                AND pvms.SourceOrderDetailWeekID = odw.ID 
                AND os.ID = pvms.SourceOrderSpotID
        LEFT JOIN (
            -- Calculate spots moved to a package vehicle
            SELECT TargetPackageVehicleID, TargetOrderDetailWeekID, TargetOrderSpotID, 
                   SUM(Spots) AS SpotsMovedTo
            FROM dbo.PackageVehicleMove
            WHERE TargetOrderDetailWeekID IS NOT NULL AND TargetOrderSpotID IS NOT NULL 
                  AND TargetPackageVehicleID IS NOT NULL
            GROUP BY TargetPackageVehicleID, TargetOrderDetailWeekID, TargetOrderSpotID
        ) pvmt ON pvmt.TargetPackageVehicleID = pv.ID 
                AND pvmt.TargetOrderDetailWeekID = odw.ID 
                AND os.ID = pvmt.TargetOrderSpotID
        WHERE os.RunDate BETWEEN @runDate AND DATEADD(DAY, @daystoCalculate, @runDate) 
              AND oh.IsFlex = 0 
              AND p.PackageTypeID <> 6 
              AND oh.OrderStatusID IN (1, 2);
    END
    ELSE -- Calculate inventory only for spots that were moved
    BEGIN
        INSERT INTO #InventoryUsageByVehicleForCursor
        (OrderSpotID, PackageVehicleID, StartTime, EndTime, Monday, Tuesday, Wednesday, 
         Thursday, Friday, Saturday, Sunday, StartDate, EndDate, SpotMultiplier, VehicleID, 
         SpotTypeID, SpotLength, WeekStartDate, CompanyTypeID, SchedulerTypeID, 
         OrderStatusID, NonSpot, OrderHeaderID, OrderDetailWeekID)
        
        -- Select records for moved spots
        SELECT DISTINCT os.ID, pv.ID, pv.StartTime, pv.EndTime, pv.Monday, pv.Tuesday, 
               pv.Wednesday, pv.Thursday, pv.Friday, pv.Saturday, pv.Sunday, 
               pv.StartDate, ISNULL(pv.EndDate, '2050-01-01'), 
               pv.SpotMultiplier - ISNULL(pvms.SpotsMovedFrom, 0) + ISNULL(pvmt.SpotsMovedTo, 0), 
               pv.VehicleID, CASE WHEN st.IncludeInAvailsReport = 1 THEN NULL ELSE pv.SpotTypeID END, 
               od.Length, odw.StartDate, oh.CompanyTypeID, oh.SchedulerTypeID, 
               oh.OrderStatusID, od.NonSpot, od.OrderHeaderID, odw.ID
        FROM OrderHeader oh
        INNER JOIN OrderDetail od ON od.OrderHeaderID = oh.ID
        INNER JOIN OrderDetail