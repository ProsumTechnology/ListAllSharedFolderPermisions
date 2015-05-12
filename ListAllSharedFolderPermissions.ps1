Param
(
	[Parameter(Mandatory=$false)][Alias('Dir')][Array]$DirList="\\proximus.prosum.com\DFS",
	[Parameter(Mandatory=$false)][Alias('OutFile')][String]$Output = "Results.csv",
    [Parameter(Mandatory=$false)][Alias('OutType')][ValidateSet("CSV","HTML")][String]$OutputType = "CSV",
    [Parameter(Mandatory=$false)][String]$Depth="10"
)

#Check for and load NTFSSecurity module if it's missing
IF (!(Get-Module NTFSSecurity)) {
    write-verbose "Importing the NTFSSecurity Module ..."
    Try {
        Import-Module .\NTFSSecurity\NTFSSecurity.psd1
        }
    Catch {
        Throw "unable to load the NTFSSecurity PowerShell Module. Please ensure the modules exist under .\NTFSSecurity or import them manually"
        }
    }

IF (!(Get-Module DFSN)) {
    write-verbose "Importing the DFSN Module ..."
    Try {
        Import-Module DFSN
        }
    Catch {
        Throw "unable to load the DFSN PowerShell Module.  Please use add-remove programs to add DFS name space management tools or run from a server with these tools installed"
        }
    }

#This function solves the lack of depth selection in Get-ChildItem (won't be needed in PSv5)
write-verbose "creating custom function to crawl folders to specified depth ..."
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

#Start with an empty array to be populated
[array]$ChildList = $null

#Add each defined URL to array with child paths
write-verbose "Building full directory tree (this could take awhile) ..."

foreach($DL in $DirList) {
    $ChildList+=$DL
    $ChildList+=(Get-ChildItemToDepth -Path $DL -ToDepth $Depth)
    }


#Crawl Array and attempt to identify all DFS paths with valid UNC Targets
write-verbose "attempting to find and translate any DFS namespaces to UNC paths ... "
[array]$DFSConvert = @()
foreach ($DL in $ChildList) {
    If (Get-DfsnFolderTarget $DL -ErrorAction SilentlyContinue| where {$_.State -eq "Online"}) {
        $NewPath = (Get-DfsnFolderTarget $DL -ErrorAction SilentlyContinue| where {$_.State -eq "Online"})[0]
        write-verbose "path $DL needs to be updated to $NewPath ..."
        $DFSConvert+=$NewPath
        }
    Else {
        $NewPath=$null
        write-verbose "Path $DL is not a folder target"
        }
    }

#This simple sort makes sure we remap longer filename paths first and avoid breaking by mapping shorter paths first
$DFSConvert = $DFSConvert | sort {$_Path.length}

#Build ChildList2 with new values
[array]$ChildList2=$null
write-verbose "Updating DFSNamespace links ..."
$ChildList | ForEach-Object {
    $Source = $_
    $newvalue=$null
    ForEach ($DFS in $DFSConvert) {
        $Test=$DFS.Path
        $Testinj = [regex]::escape($Test)
        $TargetTest = $DFS.TargetPath
        If ($Source -like $Test+"*") {
            Write-verbose "need to update $_ with $targettest..."
            $NewValue = ($_ -replace($Testinj,$TargetTest))
            }
        }
    if ($newvalue -eq $null) {$ChildList2+=$Source}
    else {$ChildList2+=$newvalue}
    }

#combine the two lists into a FinalList
$stepsstop=$ChildList.count-1
$range=0..$stepsstop
foreach ($i in $range) {
    $finallist+= @{$ChildList[$i] = $ChildList2[$i]}
    }

#Gather all non-inherited permissions and save based on defined type
write-verbose "Generating report..."
Switch ($OutputType) {
    HTML {get-ntfsaccess -Path $ChildList2 | where {$_.IsInherited -eq $false} | Select FullName, AccountType, Account, AccessControlType, AccessRights | ConvertTo-HTML | Out-File $Output}
    CSV {get-ntfsaccess -Path $ChildList2 | where {$_.IsInherited -eq $false} | Select FullName, AccountType, Account, AccessControlType, AccessRights | Export-Csv $Output}
    }

write-verbose "Done!"
