<#
.SYNOPSIS
    Modifies the TotalTimeElapsed value in MechWarrior 5: Mercenaries binary save files.

.DESCRIPTION
    This script locates the TotalTimeElapsed IntProperty in a MW5 save file and
    updates it to manipulate the in-game calendar. Day 0 is the epoch: May 27, 3015.

.PARAMETER SaveFile
    Path to the MechWarrior 5 save file (.sav).

.PARAMETER Operation
    The operation to perform: Set, Add, Subtract, or SetDate.

.PARAMETER Value
    The number of units to use with Set, Add, or Subtract operations.

.PARAMETER Unit
    The time unit for Add/Subtract operations: Days (default), Weeks, or Months.
    Months are calculated as calendar months relative to the current in-game date.

.PARAMETER Date
    The in-game calendar date to set (yyyy-MM-dd). Used with the SetDate operation.
    Must not be earlier than 3015-05-27.

.PARAMETER WhatIf
    Preview the change without writing anything to disk.

.EXAMPLE
    .\Update-DaysGoneBy.ps1 save.sav -Operation Set -Value 0 -WhatIf

.EXAMPLE
    .\Update-DaysGoneBy.ps1 save.sav -Operation Add -Value 30

.EXAMPLE
    .\Update-DaysGoneBy.ps1 save.sav -Operation Add -Value 2 -Unit Weeks

.EXAMPLE
    .\Update-DaysGoneBy.ps1 save.sav -Operation Subtract -Value 3 -Unit Months

.EXAMPLE
    .\Update-DaysGoneBy.ps1 save.sav -Operation SetDate -Date "3016-06-15"
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory, Position = 0)]
    [string]$SaveFile,

    [Parameter(Mandatory)]
    [ValidateSet('Set', 'Add', 'Subtract', 'SetDate')]
    [string]$Operation,

    [Parameter()]
    [int]$Value,

    [Parameter()]
    [ValidateSet('Days', 'Weeks', 'Months')]
    [string]$Unit = 'Days',

    [Parameter()]
    [string]$Date
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Epoch: Day 0 = May 27, 3015 (in-game calendar)
# We use a proleptic Gregorian offset; only *differences* between in-game
# dates matter, so we anchor to a real DateTime for arithmetic purposes.
# The real date used is arbitrary — only the day-delta is meaningful.
$EPOCH = [datetime]::new(3015, 5, 27)

# The exact byte pattern that precedes the TotalTimeElapsed value.
# Breakdown:
#   11000000                           - Name length (17)
#   546f74616c54696d65456c617073656400 - "TotalTimeElapsed\0"
#   0c000000                           - Type name length (12)
#   496e7450726f706572747900           - "IntProperty\0"
#   04000000                           - Value size (4 bytes)
#   00000000                           - Padding field
$PATTERN_HEX = '11000000546f74616c54696d65456c6170736564000c000000496e7450726f706572747900040000000000000000'
$PATTERN_BYTES = [byte[]] ($PATTERN_HEX -replace '..', '0x$&,' -split ',' |
    Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) })

# The actual int32 value sits immediately after the pattern (no extra skip needed;
# the 4-byte padding is already included at the end of the pattern above).
$VALUE_OFFSET_FROM_PATTERN_END = 0

# ---------------------------------------------------------------------------
# Helper: Search for a byte pattern inside a byte array
# ---------------------------------------------------------------------------
function Find-Pattern {
    param (
        [byte[]]$Haystack,
        [byte[]]$Needle
    )

    $hLen = $Haystack.Length
    $nLen = $Needle.Length

    for ($i = 0; $i -le ($hLen - $nLen); $i++) {
        $found = $true
        for ($j = 0; $j -lt $nLen; $j++) {
            if ($Haystack[$i + $j] -ne $Needle[$j]) {
                $found = $false
                break
            }
        }
        if ($found) { return $i }
    }
    return -1
}

# ---------------------------------------------------------------------------
# Helper: Read a little-endian int32 from a byte array at a given offset
# ---------------------------------------------------------------------------
function Read-Int32LE {
    param ([byte[]]$Buffer, [int]$Offset)
    return [System.BitConverter]::ToInt32($Buffer, $Offset)
}

# ---------------------------------------------------------------------------
# Helper: Write a little-endian int32 into a byte array at a given offset
# ---------------------------------------------------------------------------
function Write-Int32LE {
    param ([byte[]]$Buffer, [int]$Offset, [int]$NewValue)
    $bytes = [System.BitConverter]::GetBytes([int32]$NewValue)
    [System.Array]::Copy($bytes, 0, $Buffer, $Offset, 4)
}

# ---------------------------------------------------------------------------
# Helper: Convert in-game days to an in-game calendar date string
# ---------------------------------------------------------------------------
function Convert-DaysToDate {
    param ([int]$Days)
    # Shift year by 1000 years for display (3015 - 2015)
    $base = [datetime]::new(2015, 5, 27)
    $real = $base.AddDays($Days)
    return "{0:D4}-{1:D2}-{2:D2}" -f ($real.Year + 1000), $real.Month, $real.Day
}

# ---------------------------------------------------------------------------
# Helper: Convert an in-game calendar date string to days since epoch
# ---------------------------------------------------------------------------
function Convert-DateToDays {
    param ([string]$DateStr)

    if ($DateStr -notmatch '^\d{4}-\d{2}-\d{2}$') {
        throw "Date must be in yyyy-MM-dd format (e.g. 3016-06-15). Got: '$DateStr'"
    }

    $parts = $DateStr -split '-'
    $year  = [int]$parts[0]
    $month = [int]$parts[1]
    $day   = [int]$parts[2]

    # Validate components before constructing a shifted DateTime
    if ($month -lt 1 -or $month -gt 12) { throw "Invalid month: $month" }
    if ($day   -lt 1 -or $day   -gt 31) { throw "Invalid day: $day" }

    # Shift: subtract 1000 from year to get a real DateTime for arithmetic
    $shiftedYear = $year - 1000
    if ($shiftedYear -lt 1 -or $shiftedYear -gt 9999) {
        throw "Year $year is out of the supported range."
    }

    $targetReal  = [datetime]::new($shiftedYear, $month, $day)
    $epochReal   = [datetime]::new($EPOCH.Year - 1000, $EPOCH.Month, $EPOCH.Day)

    $delta = ($targetReal - $epochReal).Days

    if ($delta -lt 0) {
        throw "Date '$DateStr' is before the epoch (3015-05-27). Dates cannot be earlier than the epoch."
    }
    return $delta
}

# ---------------------------------------------------------------------------
# Helper: Convert a unit/value offset to a day delta, given a current day
# count as context (required for calendar-aware month arithmetic).
# ---------------------------------------------------------------------------
function Convert-UnitToDays {
    param (
        [int]$Amount,       # Signed: positive = forward, negative = backward
        [string]$Unit,
        [int]$CurrentDays   # Only used for Months; ignored for Days/Weeks
    )

    switch ($Unit) {
        'Days'   { return $Amount }
        'Weeks'  { return $Amount * 7 }
        'Months' {
            # Reconstruct the current in-game date as a shifted real DateTime,
            # add the requested number of calendar months, then measure the
            # resulting day delta. This correctly handles variable month lengths
            # (e.g. adding 1 month to Jan 31 yields Feb 28/29, not Mar 2/3).
            $base        = [datetime]::new(2015, 5, 27)
            $currentReal = $base.AddDays($CurrentDays)
            $targetReal  = $currentReal.AddMonths($Amount)
            return ($targetReal - $currentReal).Days
        }
        default { throw "Unknown unit: '$Unit'" }
    }
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

# -Unit is only meaningful for Add/Subtract; warn if supplied with others.
if ($PSBoundParameters.ContainsKey('Unit') -and $Operation -notin 'Add', 'Subtract') {
    Write-Warning "-Unit is only applicable to 'Add' and 'Subtract' operations and will be ignored."
}

# Resolve and verify the save file path
$resolvedPath = Resolve-Path -LiteralPath $SaveFile -ErrorAction SilentlyContinue
if (-not $resolvedPath) {
    Write-Error "Save file not found: '$SaveFile'"
    exit 1
}
$SaveFile = $resolvedPath.Path

switch ($Operation) {
    'Set' {
        if (-not $PSBoundParameters.ContainsKey('Value')) {
            Write-Error "-Value is required for the 'Set' operation."
            exit 1
        }
        if ($Value -lt 0) {
            Write-Warning "Value $Value is negative; clamping to 0."
            $Value = 0
        }
    }
    'Add' {
        if (-not $PSBoundParameters.ContainsKey('Value')) {
            Write-Error "-Value is required for the 'Add' operation."
            exit 1
        }
        if ($Value -lt 0) {
            Write-Error "-Value must be a positive number for 'Add'. Use 'Subtract' for negative offsets."
            exit 1
        }
    }
    'Subtract' {
        if (-not $PSBoundParameters.ContainsKey('Value')) {
            Write-Error "-Value is required for the 'Subtract' operation."
            exit 1
        }
        if ($Value -lt 0) {
            Write-Error "-Value must be a positive number for 'Subtract'."
            exit 1
        }
    }
    'SetDate' {
        if (-not $PSBoundParameters.ContainsKey('Date')) {
            Write-Error "-Date is required for the 'SetDate' operation."
            exit 1
        }
    }
}

# ---------------------------------------------------------------------------
# Load the save file
# ---------------------------------------------------------------------------
Write-Verbose "Reading save file: $SaveFile"
$fileBytes = [System.IO.File]::ReadAllBytes($SaveFile)
Write-Verbose "File size: $($fileBytes.Length) bytes"

# ---------------------------------------------------------------------------
# Locate the pattern
# ---------------------------------------------------------------------------
$patternIndex = Find-Pattern -Haystack $fileBytes -Needle $PATTERN_BYTES

if ($patternIndex -lt 0) {
    Write-Error @"
Pattern not found in '$SaveFile'.
The file may not be a valid MW5 save, may be compressed, or the format has changed.
Expected pattern (hex): $PATTERN_HEX
"@
    exit 1
}

Write-Verbose ("Pattern found at byte offset: $patternIndex (0x{0:X})" -f $patternIndex)

$valueOffset = $patternIndex + $PATTERN_BYTES.Length + $VALUE_OFFSET_FROM_PATTERN_END
Write-Verbose ("Value offset: $valueOffset (0x{0:X})" -f $valueOffset)

if ($valueOffset + 4 -gt $fileBytes.Length) {
    Write-Error "Value offset $valueOffset is beyond the end of the file. The save file may be truncated."
    exit 1
}

# ---------------------------------------------------------------------------
# Read the current value
# ---------------------------------------------------------------------------
$currentDays = Read-Int32LE -Buffer $fileBytes -Offset $valueOffset
$currentDate = Convert-DaysToDate -Days $currentDays

Write-Host ""
Write-Host "  Save File : $SaveFile"
Write-Host "  Current   : $currentDays days  ($currentDate)"

# ---------------------------------------------------------------------------
# Calculate the new value
# ---------------------------------------------------------------------------
$newDays = switch ($Operation) {
    'Set'     { $Value }
    'Add'     {
        $delta = Convert-UnitToDays -Amount $Value -Unit $Unit -CurrentDays $currentDays
        $currentDays + $delta
    }
    'Subtract' {
        $delta = Convert-UnitToDays -Amount $Value -Unit $Unit -CurrentDays $currentDays
        $currentDays - $delta
    }
    'SetDate' { Convert-DateToDays -DateStr $Date }
}

# Clamp: must be >= 0 and fit in int32
$INT32_MAX = [int]::MaxValue
if ($newDays -lt 0) {
    Write-Warning "Calculated value ($newDays) is negative; clamping to 0."
    $newDays = 0
}
if ($newDays -gt $INT32_MAX) {
    Write-Warning "Calculated value ($newDays) exceeds int32 max; clamping to $INT32_MAX."
    $newDays = $INT32_MAX
}

$newDate = Convert-DaysToDate -Days $newDays

# Build a readable description of the operation for the summary line
$opDescription = switch ($Operation) {
    'Set'      { "Set $Value day(s)" }
    'Add'      { "Add $Value $Unit" }
    'Subtract' { "Subtract $Value $Unit" }
    'SetDate'  { "SetDate ($Date)" }
}

Write-Host "  Operation : $opDescription"
Write-Host "  New Value : $newDays days  ($newDate)"
Write-Host ""

# ---------------------------------------------------------------------------
# Write the new value (honours -WhatIf)
# ---------------------------------------------------------------------------
if ($PSCmdlet.ShouldProcess($SaveFile, "Write TotalTimeElapsed = $newDays (was $currentDays)")) {
    Write-Int32LE -Buffer $fileBytes -Offset $valueOffset -NewValue $newDays
    [System.IO.File]::WriteAllBytes($SaveFile, $fileBytes)
    Write-Host "  [OK] Save file updated successfully."
} else {
    Write-Host "  [WhatIf] No changes written to disk."
}

Write-Host ""
