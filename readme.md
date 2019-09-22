
| Master Branch | Development Branch |
| ------------- |-------------|
|[![Build status](https://ci.appveyor.com/api/projects/status/hmbxfmswdm77td2i/branch/master?svg=true)](https://ci.appveyor.com/project/sanderstad/pstsqlttestgenerator/branch/master)     | [![Build status](https://ci.appveyor.com/api/projects/status/hmbxfmswdm77td2i/branch/development?svg=true)](https://ci.appveyor.com/project/sanderstad/pstsqlttestgenerator/branch/development) |


# PStSQLtTestGenerator

# What does it do

<img style="float: right; height: 180px;" src="resources/logo180px.png">

Unit testing is fairly new to databases and more and more companies are implementing it into their development process.
The downside is that the existing objects do not have any unit tests yet.

That's where this PowerShell module comes in. This module makes it possible for you to generate basic unit tests for database objects.

Tests like:

- Database Collation
- Objects Existence
- Function Parameters
- Stored Procedure Parameters
- Table Columns
- View Columns

## How does it work

The modules works by iterating through database objects and create tests according to the type of object.

Based on a specific template for each test, it will create a ".sql" for each test with the correct content.

For instance, all the functions, stored procedures, tables and views will have a test to check if they exists the next time the tSQLt unit test runs.

Let's take the table "dbo.Customer". This table would get a test called "test If table dbo.Customer exists Expect Success.sql".
This test file would contain content similar to this:

```sql
/*
Description:
Test if the table dbo.Customer exists

Changes:
Date		Who					Notes
----------	---					--------------------------------------------------------------
9/18/2019	sstad				Initial test
*/
CREATE PROCEDURE [TestBasic].[test If table dbo.Customer exists Expect Success]
AS
BEGIN
    SET NOCOUNT ON;

    ----- ASSERT -------------------------------------------------
    EXEC tSQLt.AssertObjectExists @ObjectName = N'dbo.Customer';
END;

```

## How to run the module

The main command to get all the tests is `Invoke-PSTGTestGenerator`.

To get all the tests run the following command:

```powershell
Invoke-PSTGTestGenerator -SqlInstance [yourinstance] -Database [yourdatabase] -OutputPath [testfolder]
```

That's all that is to it. The tests will all be written to the designated folder.
You can then copy these to your SSDT project or run the scripts to create the the tests in your database

For more help and information about any particular command, run the Get-Help command, i.e.:

```powershell
Get-Help Invoke-PSTGTestGenerator
```