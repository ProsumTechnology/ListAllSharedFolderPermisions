Param
(
	[Parameter(Mandatory=$false)][Alias('Dir')][Array]$DirList="\\ES-SSCCM-01\DSL",
	[Parameter(Mandatory=$false)][Alias('OutFile')][String]$Output = "Results.html",
    [Parameter(Mandatory=$false)][Alias('OutType')][ValidateSet("CSV","HTML")][String]$OutputType = "HTML",
    [Parameter(Mandatory=$false)][String]$Depth="255"
)

#Check for and load NTFSSecurity module if it's missing
IF (!(Get-Module NTFSSecurity)) {
    Import-Module .\NTFSSecurity\NTFSSecurity.psd1
    }

#Start with an empty array to be populated
[array]$ChildList = $null

#Add each defined URL to array with child paths
foreach($DL in $DirList) {
    $ChildList+=$DL
    $ChildList+=(Get-ChildItemToDepth -Path $DL -ToDepth $Depth)
    }

#Gather all non-inherited permissions and save based on defined type
Switch ($OutputType) {
    HTML {get-ntfsaccess -Path $ChildList | where {$_.IsInherited -eq $false} | Select FullName, AccountType, Account, AccessControlType, AccessRights | ConvertTo-HTML | Out-File $Output}
    CSV {get-ntfsaccess -Path $ChildList | where {$_.IsInherited -eq $false} | Select FullName, AccountType, Account, AccessControlType, AccessRights | Export-Csv $Output}
    }


#This function solves the lack of depth selection in Get-ChildItem (won't be needed in PSv5)
function Get-ChildItemToDepth {
  param(
    [String]$Path = $PWD,
    [Byte]$ToDepth = 255,
    [Byte]$CurrentDepth = 0,
    [Switch]$DebugMode
  )
 
  $CurrentDepth++
  if ($DebugMode) { $DebugPreference = "Continue" }
 
  Get-ChildItem $Path -Directory | ForEach-Object {
    $_.FullName
    if ($_.PsIsContainer) {
      if ($CurrentDepth -le $ToDepth) {
        # Callback to this function
        Get-ChildItemToDepth -Path $_.FullName -ToDepth $ToDepth -CurrentDepth $CurrentDepth
      } else {
        Write-Debug $("Skipping GCI for Folder: $($_.FullName) " +
          "(Why: Current depth $CurrentDepth vs limit depth $ToDepth)")
      }
    }
  }
}