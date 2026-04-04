# MW5 Save Editor - TotalTimeElapsed Modifier

A PowerShell script to modify the in-game calendar date in MechWarrior 5: Mercenaries binary save files.

## Overview

This script locates and updates the `TotalTimeElapsed` IntProperty value in MW5 save files, allowing you to manipulate the in-game calendar. Day 0 corresponds to **May 27, 3015**.

## Features

- **Set** a specific number of elapsed days
- **Add** days to the current value
- **Subtract** days from the current value
- **SetDate** using a calendar date (YYYY-MM-DD format)
- **WhatIf** support to preview changes before writing
- Automatic clamping to valid range (0 to 2,147,483,647 days)
- Safe pattern-based binary editing (no external dependencies)

## Prerequisites

- PowerShell 5.1 or later (Windows) or PowerShell 7+ (cross-platform)
- Read/write access to your MW5 save files

## Save File Location

Typical save file locations:

| Platform | Path |
|----------|------|
| Windows (Steam) | `%LOCALAPPDATA%\MW5Mercs\Saved\SaveGames\` |
| Windows (GOG) | `%USERPROFILE%\Documents\My Games\MW5Mercs\MW5Mercs\Saved\SaveGames\` |
| Steam Deck / Linux | `~/.local/share/Steam/steamapps/compatdata/784080/pfx/drive_c/users/steamuser/Local Settings/Application Data/MW5Mercs/Saved/SaveGames/` |

## Usage

### Basic Syntax

```powershell
.\Update-DaysGoneBy.ps1 <SaveFile> -Operation <Operation> [parameters]
```

### Operations

#### Set - Set exact days elapsed

```powershell
.\Update-DaysGoneBy.ps1 save.sav -Operation Set -Value 0 -WhatIf
.\Update-DaysGoneBy.ps1 save.sav -Operation Set -Value 365
```

#### Add - Add days to current value

```powershell
.\Update-DaysGoneBy.ps1 save.sav -Operation Add -Value 30
```

#### Subtract - Subtract days from current value

```powershell
.\Update-DaysGoneBy.ps1 save.sav -Operation Subtract -Value 10
```

#### SetDate - Set to a specific calendar date

```powershell
.\Update-DaysGoneBy.ps1 save.sav -Operation SetDate -Date "3016-06-15"
```

### Example Output

```
  Save File : C:\Users\Example\Saved Games\MW5Mercs\SaveGames\Campaign1.sav
  Current   : 125 days  (3015-09-29)
  Operation : Add 30 day(s)
  New Value : 155 days  (3015-10-29)

  [OK] Save file updated successfully.
```

## Important Notes

1. **Always back up your saves** before modifying them
2. The epoch is fixed at **May 27, 3015** (Day 0)
3. Dates before the epoch are not allowed
4. Year 10,000+ is not supported (int32 limitation)
5. The script validates that the target file is a valid MW5 save before attempting modifications

## How It Works

The script searches for the exact byte pattern that precedes the `TotalTimeElapsed` value:

```
Pattern (hex): 11000000546f74616c54696d65456c6170736564000c000000496e7450726f706572747900040000000000000000
```

This pattern represents:
- Name length (17): "TotalTimeElapsed\0"
- Type name length (12): "IntProperty\0"  
- Value size (4 bytes)
- Padding field

The 4-byte integer value immediately follows this pattern and is modified in-place.

## Error Handling

| Error | Likely Cause |
|-------|---------------|
| `Save file not found` | Invalid file path |
| `Pattern not found` | File is not a valid MW5 save, may be corrupted or compressed |
| `Date must be in yyyy-MM-dd format` | Invalid date format |
| `Date is before the epoch` | Cannot set date earlier than May 27, 3015 |
| `Value offset is beyond file end` | Corrupted or truncated save file |

## License

This script is provided as-is for educational and personal use. Modify your saves at your own risk.

## Contributing

Issues and pull requests are welcome for:
- Support for compressed save formats
- Additional property editing capabilities
- Cross-platform improvements

---

*Note: This tool modifies binary save files. Always create backups before use.*
