/*
    Stored Procedure: [dbo].[CalculateInventoryUsageByVehicle]
    Description: This stored procedure calculates and updates the inventory usage by vehicle. It processes vehicle inventory data,
    considering any inventory movements, and updates the related tables to reflect accurate inventory levels.

    Author: Adeola Idowu
    Created On: CURRENT_TIMESTAMP
    Last Modified: CURRENT_TIMESTAMP
*/

USE [YourDatabase] -- Replace with your actual database name
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROC [dbo].[CalculateInventoryUsageByVehicle] 
    @runDate DATE = NULL,
    @daysToCalculate INT = 0,
    @spotsMoved INT
AS
BEGIN
    -- Declare necessary variables
    DECLARE @tryDate DATE, 
            @CompanyTypeID INT,
            @orderSpotID INT,
            @schedulerID INT,
            @PackageVehicleID INT,
            @schedulerOrderSpotID INT,
            @packageVehicleSpotMultiplier INT,
            @packageVehicleStartTime TIME,
            @packageVehicleEndTime TIME,
            @packageVehicleStartDate DATE,
            @packageVehicleEndDate DATE,
            @packageVehicleMonday BIT,
            @packageVehicleTuesday BIT,
            @packageVehicleWednesday BIT,
            @packageVehicleThursday BIT,
            @packageVehicleFriday BIT,
            @packageVehicleSaturday BIT,
            @packageVehicleSunday BIT,
            @programVehicleMonday BIT,
            @programVehicleTuesday BIT,
            @programVehicleWednesday BIT,
            @programVehicleThursday BIT,
            @programVehicleFriday BIT,
            @programVehicleSaturday BIT,
            @programVehicleSunday BIT,
            @OrderStatusID INT,
            @OrderHeaderID INT,
            @NonSpot CHAR(1),
            @programVehicleStartTime TIME,
            @programVehicleEndTime TIME,
            @vehicleID INT,
            @firstLegacySellTime TIME,
            @legacySellTime TIME,
            @usage INT,
            @programVehicleSpotMultiplier INT,
            @programVehicleID INT,
            @programSpotTypeID INT,
            @SpotTypeID INT,
            @SpotLength INT,
            @WeekStartDate DATE,
            @SchedulerTypeID INT;

    -- Create temporary tables for processing
    CREATE TABLE #InventoryUsageByVehicleForCursor (
        OrderSpotID INT,
        PackageVehicleID INT,
        StartTime TIME(0),
        EndTime TIME(0),
        Monday BIT,
        Tuesday BIT,
        Wednesday BIT,
        Thursday BIT,
        Friday BIT,
        Saturday BIT,
        Sunday BIT,
        StartDate DATE,
        EndDate DATE,
        SpotMultiplier INT,
        VehicleID INT,
        SpotTypeID INT,
        SpotLength INT,
        WeekStartDate DATE,
        CompanyTypeID INT,
        SchedulerTypeID INT,
        OrderStatusID INT,
        NonSpot CHAR(1),
        OrderHeaderID INT,
        OrderDetailWeekID INT
    );

    CREATE TABLE #PackageVehicleMoveInventoryProcessed (
        PackageVehicleID INT,
        OrderDetailWeekID INT,
        OrderSpotID INT,
        WeekStart DATE,
        Spots INT
    );

    -- Insert data into the temporary table based on PackageVehicleMove table
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

    -- Process based on the @spotsMoved parameter
    IF (@spotsMoved = 0)
    BEGIN
        -- Insert all relevant inventory data when no spots have been moved
        INSERT INTO #InventoryUsageByVehicleForCursor
        (OrderSpotID, PackageVehicleID, StartTime, EndTime, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday, StartDate, EndDate, SpotMultiplier, VehicleID, SpotTypeID, SpotLength, WeekStartDate, CompanyTypeID, SchedulerTypeID, OrderStatusID, NonSpot, OrderHeaderID, OrderDetailWeekID)
        SELECT OrderSpotID, PackageVehicleID, StartTime, EndTime, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday, StartDate, EndDate, SpotMultiplier, VehicleID, SpotTypeID, SpotLength, WeekStartDate, CompanyTypeID, SchedulerTypeID, OrderStatusID, NonSpot, OrderHeaderID, OrderDetailWeekID
        FROM (
            SELECT DISTINCT
                os.ID AS OrderSpotID,
                pv.ID AS PackageVehicleID,
                pv.StartTime,
                pv.EndTime,
                pv.Monday,
                pv.Tuesday,
                pv.Wednesday,
                pv.Thursday,
                pv.Friday,
                pv.Saturday,
                pv.Sunday,
                pv.StartDate,
                ISNULL(pv.EndDate, '2050-01-01') AS EndDate,
                pv.SpotMultiplier - ISNULL(pvms.SpotsMovedFrom, 0) + ISNULL(pvmt.SpotsMovedTo, 0) AS SpotMultiplier,
                pv.VehicleID,
                CASE WHEN st.IncludeInAvailsReport = 1 THEN NULL ELSE pv.SpotTypeID END AS SpotTypeID,
                od.[Length] AS SpotLength,
                odw.StartDate AS WeekStartDate,
                oh.CompanyTypeID,
                oh.SchedulerTypeID,
                oh.OrderStatusID,
                od.ID AS OrderDetailID,
                od.NonSpot,
                od.OrderHeaderID,
                odw.ID AS OrderDetailWeekID
            FROM OrderHeader AS oh
            INNER JOIN OrderDetail AS od ON od.OrderHeaderID = oh.ID
            INNER JOIN OrderDetailWeek AS odw ON odw.OrderDetailID = od.ID
            INNER JOIN OrderSpot AS os ON os.OrderDetailWeekID = odw.ID
            INNER JOIN Package AS p ON p.ID = od.PackageID
            INNER JOIN PackageVehicle AS pv ON pv.PackageID = p.ID
            INNER JOIN Vehicle AS v ON v.ID = pv.VehicleID
            LEFT JOIN dbo.SpotType st ON st.ID = pv.SpotTypeID
            LEFT JOIN (
                SELECT SourcePackageVehicleID, SourceOrderSpotID, SourceOrderDetailWeekID, SUM(Spots) AS SpotsMovedFrom
                FROM dbo.PackageVehicleMove
                WHERE SourceOrderSpotID IS NOT NULL AND SourcePackageVehicleID IS NOT NULL AND SourceOrderDetailWeekID IS NOT NULL
                GROUP BY SourcePackageVehicleID, SourceOrderSpotID, SourceOrderDetailWeekID
            ) pvms ON pvms.SourcePackageVehicleID = pv.ID AND pvms.SourceOrderDetailWeekID = odw.ID AND os.ID = pvms.SourceOrderSpotID
            LEFT JOIN (
                SELECT TargetPackageVehicleID, TargetOrderDetailWeekID, TargetOrderSpotID, SUM(Spots) AS SpotsMovedTo
                FROM dbo.PackageVehicleMove
                WHERE TargetOrderDetailWeekID IS NOT NULL AND TargetOrderSpotID IS NOT NULL AND TargetPackageVehicleID IS NOT NULL
                GROUP BY TargetPackageVehicleID, TargetOrderDetailWeekID, TargetOrderSpotID
            ) pvmt ON pvmt.TargetPackageVehicleID = pv.ID AND pvmt.TargetOrderDetailWeekID = odw.ID AND os.ID = pvmt.TargetOrderSpotID
            WHERE os.RunDate BETWEEN @runDate AND DATEADD(DAY, @daysToCalculate, @runDate)
              AND oh.IsFlex = 0
              AND p.PackageTypeID <> 6
              AND oh.OrderStatusID IN (1, 2)
            UNION ALL
            SELECT DISTINCT
                pvmos.SourceOrderSpotID AS OrderSpotID,
                pv.ID AS PackageVehicleID,
                pv.StartTime,
                pv.EndTime,
                pv.Monday,
                pv.Tuesday,
                pv.Wednesday,
                pv.Thursday,
                pv.Friday,
                pv.Saturday,
                pv.Sunday,
                pvmos.TargetWeek AS StartDate,
                DATEADD(DAY, 6, pvmos.TargetWeek) AS EndDate,
                pvmos.Spots AS SpotMultiplier,
                pv.VehicleID,
                CASE WHEN st.IncludeInAvailsReport = 1 THEN NULL ELSE pv.SpotTypeID END AS SpotTypeID,
                od.[Length] AS SpotLength,
                pvmos.TargetWeek AS WeekStartDate,
                oh.CompanyTypeID,
                oh.SchedulerTypeID,
                oh.OrderStatusID,
                od.ID AS OrderDetailID,
                od.NonSpot,
                od.OrderHeaderID,
                NULL AS OrderDetailWeekID
            FROM OrderHeader AS oh
            INNER JOIN OrderDetail AS od ON od.OrderHeaderID = oh.ID
            INNER JOIN OrderDetailWeek AS odw ON odw.OrderDetailID = od.ID
            INNER JOIN OrderSpot AS os ON os.OrderDetailWeekID = odw.ID
            INNER JOIN Package AS p ON p.ID = od.PackageID
            INNER JOIN PackageVehicle AS pv ON pv.PackageID = p.ID
            INNER JOIN Vehicle AS v ON v.ID = pv.VehicleID
            LEFT JOIN dbo.SpotType st ON st.ID = pv.SpotTypeID
            LEFT JOIN dbo.PackageVehicleMove pvmos ON pv.ID = pvmos.SourcePackageVehicleID AND pvmos.SourceOrderDetailWeekID = odw.ID AND pvmos.SourceOrderSpotID = os.ID
            WHERE pvmos.TargetWeek IS NOT NULL AND pvmos.TargetWeek BETWEEN @runDate AND DATEADD(DAY, @daysToCalculate, @runDate)
              AND oh.IsFlex = 0
              AND p.PackageTypeID <> 6
              AND oh.OrderStatusID IN (1, 2)
        ) AS InventoryData;

        -- Calculate inventory usage and update records
        UPDATE iv
        SET iv.SpotMultiplier = iv.SpotMultiplier - COALESCE(pv.SpotMultiplier, 0)
        FROM #InventoryUsageByVehicleForCursor iv
        LEFT JOIN #PackageVehicleMoveInventoryProcessed pv ON iv.PackageVehicleID = pv.PackageVehicleID
        WHERE iv.OrderSpotID = pv.OrderSpotID AND iv.StartDate BETWEEN pv.WeekStart AND DATEADD(DAY, 6, pv.WeekStart);

        -- Cleanup
        DROP TABLE #PackageVehicleMoveInventoryProcessed;
    END
    ELSE
    BEGIN
        -- Placeholder for processing logic when @spotsMoved is not zero
        -- Add logic as needed to handle specific scenarios when spots are moved
    END

    -- Cleanup
    DROP TABLE #InventoryUsageByVehicleForCursor;
END
