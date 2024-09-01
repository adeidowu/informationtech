-- Create Table: PackageVehicleMove
CREATE TABLE dbo.PackageVehicleMove (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    SourcePackageVehicleID INT NOT NULL,
    TargetPackageVehicleID INT,
    SourceOrderDetailWeekID INT NOT NULL,
    TargetOrderDetailWeekID INT,
    SourceOrderSpotID INT NOT NULL,
    TargetOrderSpotID INT,
    TargetWeek DATE,
    Spots INT NOT NULL,
    IsInventoryProcessed BIT NOT NULL
);

-- Create Table: OrderDetailWeek
CREATE TABLE dbo.OrderDetailWeek (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    OrderDetailID INT NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NOT NULL
);

-- Create Table: OrderSpot
CREATE TABLE dbo.OrderSpot (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    OrderDetailWeekID INT NOT NULL,
    RunDate DATE NOT NULL
);

-- Create Table: OrderHeader
CREATE TABLE dbo.OrderHeader (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    CompanyTypeID INT NOT NULL,
    SchedulerTypeID INT NOT NULL,
    OrderStatusID INT NOT NULL,
    IsFlex BIT NOT NULL
);

-- Create Table: OrderDetail
CREATE TABLE dbo.OrderDetail (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    OrderHeaderID INT NOT NULL,
    PackageID INT NOT NULL,
    [Length] INT NOT NULL,
    NonSpot CHAR(1) NOT NULL
);

-- Create Table: Package
CREATE TABLE dbo.Package (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    PackageTypeID INT NOT NULL
);

-- Create Table: PackageVehicle
CREATE TABLE dbo.PackageVehicle (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    PackageID INT NOT NULL,
    StartTime TIME NOT NULL,
    EndTime TIME NOT NULL,
    Monday BIT NOT NULL,
    Tuesday BIT NOT NULL,
    Wednesday BIT NOT NULL,
    Thursday BIT NOT NULL,
    Friday BIT NOT NULL,
    Saturday BIT NOT NULL,
    Sunday BIT NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE,
    SpotMultiplier INT NOT NULL,
    VehicleID INT NOT NULL,
    SpotTypeID INT NOT NULL
);

-- Create Table: Vehicle
CREATE TABLE dbo.Vehicle (
    ID INT IDENTITY(1,1) PRIMARY KEY
);

-- Create Table: SpotType
CREATE TABLE dbo.SpotType (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    IncludeInAvailsReport BIT NOT NULL
);