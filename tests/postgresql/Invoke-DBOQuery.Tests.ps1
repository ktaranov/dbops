Param (
    [switch]$Batch
)

if ($PSScriptRoot) { $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", ""); $here = $PSScriptRoot }
else { $commandName = "_ManualExecution"; $here = (Get-Item . ).FullName }

if (!$Batch) {
    # Is not a part of the global batch => import module
    #Explicitly import the module for testing
    Import-Module "$here\..\..\dbops.psd1" -Force; Get-DBOModuleFileList -Type internal | ForEach-Object { . $_.FullName }
}
else {
    # Is a part of a batch, output some eye-catching happiness
    Write-Host "Running PostgreSQL $commandName tests" -ForegroundColor Cyan
}

. "$here\..\constants.ps1"
# install PostgreSQL libs if needed
if (-not (Test-DBOSupportedSystem -Type PostgreSQL)) {
    Install-DBOSupportLibrary -Type PostgreSQL -Force -Scope CurrentUser 3>$null
}
$connParams = @{
    SqlInstance = $script:postgresqlInstance
    Credential  = $script:postgresqlCredential
    Database    = 'postgres'
    Type        = 'PostgreSQL'
    Silent      = $true
}

Describe "Invoke-DBOQuery PostgreSQL tests" -Tag $commandName, IntegrationTests {
    Context "Regular tests" {
        It "should run the query" {
            $query = "SELECT 1 AS A, 2 AS B UNION ALL SELECT NULL AS A, 4 AS B"
            $result = Invoke-DBOQuery -Query $query @connParams -As DataTable
            $result.A | Should -Be 1, ([DBNull]::Value)
            $result.B | Should -Be 2, 4
        }
        It "should select NULL" {
            $query = "SELECT NULL"
            $result = Invoke-DBOQuery -Query $query @connParams -As DataTable
            $result.Column1 | Should -Be ([DBNull]::Value)
        }
        It "should run the query with semicolon" {
            $query = "SELECT 1 AS A, 2 AS B;
            SELECT 3 AS A, 4 AS B"
            $result = Invoke-DBOQuery -Query $query @connParams -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run the query with semicolon as a dataset" {
            $query = "SELECT 1 AS A, 2 AS B;
            SELECT 3 AS A, 4 AS B"
            $result = Invoke-DBOQuery -Query $query @connParams -As Dataset
            $result.Tables[0].A | Should -Be 1
            $result.Tables[0].B | Should -Be 2
            $result.Tables[1].A | Should -Be 3
            $result.Tables[1].B | Should -Be 4
        }
        It "should run the query as a PSObject" {
            $query = "SELECT 1 AS A, 2 AS B UNION ALL SELECT NULL AS A, 4 AS B"
            $result = Invoke-DBOQuery -Query $query @connParams -As PSObject
            $result.A | Should -Be 1, $null
            $result.B | Should -Be 2, 4
        }
        It "should run the query as a SingleValue" {
            $query = "SELECT 1 AS A"
            $result = Invoke-DBOQuery -Query $query @connParams -As SingleValue
            $result | Should -Be 1
        }
        It "should run the query from InputFile" {
            $file1 = Join-Path 'TestDrive:' 1.sql
            $file2 = Join-Path 'TestDrive:' 2.sql
            "SELECT 1 AS A, 2 AS B" | Out-File $file1 -Force
            "SELECT 3 AS A, 4 AS B" | Out-File $file2 -Force -Encoding bigendianunicode
            $result = Invoke-DBOQuery -InputFile $file1, $file2 @connParams -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run the query from InputObject" {
            $file1 = Join-Path 'TestDrive:' 1.sql
            $file2 = Join-Path 'TestDrive:' 2.sql
            "SELECT 1 AS A, 2 AS B" | Out-File $file1 -Force
            "SELECT 3 AS A, 4 AS B" | Out-File $file2 -Force -Encoding bigendianunicode
            $result = Get-Item $file1, $file2 | Invoke-DBOQuery @connParams -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
            $result = $file1, $file2 | Invoke-DBOQuery @connParams -As DataTable
            $result[0].A | Should -Be 1
            $result[0].B | Should -Be 2
            $result[1].A | Should -Be 3
            $result[1].B | Should -Be 4
        }
        It "should run the query with custom variables" {
            $query = "SELECT '#{Test}' AS A, '#{Test2}' AS B UNION ALL SELECT '3' AS A, '4' AS B"
            $result = Invoke-DBOQuery -Query $query @connParams -As DataTable -Variables @{ Test = '1'; Test2 = '2'}
            $result.A | Should -Be '1', '3'
            $result.B | Should -Be '2', '4'
        }
        It "should connect to the server from a custom variable" {
            $query = "SELECT 1 AS A, 2 AS B UNION ALL SELECT 3 AS A, 4 AS B"
            $result = Invoke-DBOQuery -Type PostgreSQL -Database postgres -Query $query -SqlInstance '#{srv}' -Credential $script:postgresqlCredential -As DataTable -Variables @{ Srv = $script:postgresqlInstance }
            $result.A | Should -Be '1', '3'
            $result.B | Should -Be '2', '4'
        }
        It "should run the query with custom parameters" {
            $query = "SELECT @p1 AS A, @p2 AS B"
            $result = Invoke-DBOQuery -Query $query @connParams -Parameter @{ p1 = '1'; p2 = 'string'}
            $result.A | Should -Be 1
            $result.B | Should -Be string
        }
        It "should connect to a specific database" {
            $query = "SELECT current_database()"
            $result = Invoke-DBOQuery -Query $query @connParams -As SingleValue
            $result | Should -Be postgres
        }
        It "should address column names automatically" {
            $query = "SELECT 1 AS A, 2, 3"
            $result = Invoke-DBOQuery -Query $query @connParams -As DataTable
            $result.Columns.ColumnName | Should -Be @('A', 'Column1', 'Column2')
            $result.A | Should Be 1
            $result.Column1 | Should Be 2
            $result.Column2 | Should Be 3
        }
    }
    Context "Negative tests" {
        It "should throw an unknown table error" {
            $query = "SELECT * FROM nonexistent"
            { $null = Invoke-DBOQuery -Query $query @connParams } | Should throw 'relation "nonexistent" does not exist'
        }
        It "should throw a connection timeout error" {
            $query = "SELECT 1/0"
            { $null = Invoke-DBOQuery -Type PostgreSQL -Query $query -SqlInstance localhost:6493 -Credential $script:postgresqlCredential -ConnectionTimeout 1} | Should throw "The operation has timed out"
        }
        It "should fail when credentials are wrong" {
            try { Invoke-DBOQuery -Type PostgreSQL -Query 'SELECT 1' -SqlInstance $script:postgresqlInstance -Credential ([pscredential]::new('nontexistent', ([securestring]::new()))) }
            catch {$errVar = $_ }
            $errVar.Exception.Message | Should -Match 'No password has been provided|role \"nontexistent\" does not exist'
            try { Invoke-DBOQuery -Type PostgreSQL -Query 'SELECT 1' -SqlInstance $script:postgresqlInstance -UserName nontexistent -Password (ConvertTo-SecureString 'foo' -AsPlainText -Force) }
            catch {$errVar = $_ }
            $errVar.Exception.Message | Should -Match 'password authentication failed|role \"nontexistent\" does not exist'
        }
        It "should fail when input file is not found" {
            { Invoke-DBOQuery -InputFile '.\nonexistent' @connParams } | Should throw 'Cannot find path'
            { '.\nonexistent' | Invoke-DBOQuery @connParams } | Should throw 'Cannot find path'
        }
    }
}