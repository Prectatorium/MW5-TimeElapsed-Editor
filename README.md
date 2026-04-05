# MW5 Save Editor - TotalTimeElapsed Modifier

A PowerShell script to modify the in-game calendar date in MechWarrior 5: Mercenaries binary save files.

## Overview

This tool allows you to manipulate the `TotalTimeElapsed` value in MW5 save files, effectively controlling the in-game calendar date. Whether you want to fast-forward through time, rewind to earlier dates, or set a specific date, this script provides precise control over the game's timeline.

## Features

- **Multiple operations**: Set absolute values, add/subtract time, or set specific dates
- **Flexible time units**: Days, weeks, or calendar months (handles variable month lengths correctly)
- **Safe preview mode**: Use `-WhatIf` to see changes before writing
- **Automatic clamping**: Prevents invalid negative values or integer overflows
- **Calendar-aware**: Month calculations respect actual month lengths (28-31 days)

## Requirements

- **PowerShell 5.1** or later (Windows) or **PowerShell 7+** (cross-platform)
- **Uncompressed MW5 save files** (most standard saves work)
- File write permissions for the save directory

## Installation

1. Save the script as `Update-MW5Calendar.ps1` (or any name you prefer)
2. If using PowerShell's execution policy restrictions, you may need to run:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```

## Usage

### Basic Syntax

```powershell
.\Update-MW5Calendar.ps1 -SaveFile <path> -Operation <operation> [parameters]
```

### Operations

#### 1. Set Absolute Value
Set the days since epoch directly:
```powershell
.\Update-MW5Calendar.ps1 save.sav -Operation Set -Value 0
# Sets date to epoch: May 27, 3015

.\Update-MW5Calendar.ps1 save.sav -Operation Set -Value 365
# Sets date to approximately one year after start
```

#### 2. Add Time
Add time to current date:
```powershell
.\Update-MW5Calendar.ps1 save.sav -Operation Add -Value 30
# Adds 30 days

.\Update-MW5Calendar.ps1 save.sav -Operation Add -Value 2 -Unit Weeks
# Adds 2 weeks (14 days)

.\Update-MW5Calendar.ps1 save.sav -Operation Add -Value 1 -Unit Months
# Adds 1 calendar month (handles month length correctly)
```

#### 3. Subtract Time
Subtract time from current date:
```powershell
.\Update-MW5Calendar.ps1 save.sav -Operation Subtract -Value 7
# Subtracts 7 days

.\Update-MW5Calendar.ps1 save.sav -Operation Subtract -Value 3 -Unit Months
# Subtracts 3 calendar months
```

#### 4. Set Specific Date
Set to a specific in-game date:
```powershell
.\Update-MW5Calendar.ps1 save.sav -Operation SetDate -Date "3016-06-15"
# Sets date to June 15, 3016
```

### Preview Changes

Use `-WhatIf` to see what would change without modifying the file:
```powershell
.\Update-MW5Calendar.ps1 save.sav -Operation Add -Value 90 -WhatIf
```

### Verbose Output

Add `-Verbose` to see detailed debug information:
```powershell
.\Update-MW5Calendar.ps1 save.sav -Operation SetDate -Date "3018-01-01" -Verbose
```

## Understanding the Calendar

- **Epoch**: May 27, 3015 (Day 0)
- The script handles calendar months correctly:
  - January 31 + 1 month = February 28 (or 29 in leap years)
  - December + 1 month = January of next year
- Year range: 3015 to 9999 (practically unlimited within game limits)

## Save File Location

Typical save file locations:

**Windows (Steam)**:
```
%USERPROFILE%\AppData\Local\MW5Mercs\Saved\SaveGames\
```

**Windows (Game Pass)**:
```
%LOCALAPPDATA%\MW5Mercs\Saved\SaveGames\
```

**Steam Deck/Linux (Proton)**:
```
~/.steam/steam/steamapps/compatdata/784080/pfx/drive_c/users/steamuser/Local Settings/Application Data/MW5Mercs/Saved/SaveGames/
```

## Important Notes

1. **Backup your saves** before using this tool
2. The script modifies binary save files directly - corrupted saves cannot be recovered
3. Some operations may have unintended consequences on:
   - Campaign mission availability
   - Event triggers
   - NPC availability dates
   - Contract generation
4. Setting dates too far in the past (before May 27, 3015) is automatically clamped to Day 0
5. Extremely far future dates may exceed the game's internal limits (automatically clamped to 2,147,483,647 days)

## Troubleshooting

### "Pattern not found" Error
- Ensure the save file is uncompressed
- The save may be from a different game version with a different format
- Try loading and re-saving the game to ensure a standard format

### "Save file not found" Error
- Use absolute or relative paths correctly
- The save file may have a different extension (`.sav` is typical)
- Check file permissions

### Changes Not Reflecting In-Game
- Ensure the game is **completely closed** before editing
- Some cloud save systems (Steam, Epic) may overwrite your changes
- Verify you're editing the correct save file (check file timestamps)

### Month Calculation Seems Off
The script uses calendar months, not 30-day months. For example:
- Jan 15 → Feb 15 (31 days later)
- Jan 31 → Feb 28 (28 days later in non-leap year)

This matches real-world calendar behavior but may differ from simplified game mechanics.

## Technical Details

The script works by:
1. Locating the `TotalTimeElapsed` IntProperty in the binary save structure
2. Reading the current 32-bit integer value (days since epoch)
3. Calculating the new value based on the requested operation
4. Writing the value back in little-endian format

**Byte pattern** (hex):
```
11 00 00 00 54 6F 74 61 6C 54 69 6D 65 45 6C 61 70 73 65 64 00
0C 00 00 00 49 6E 74 50 72 6F 70 65 72 74 79 00
04 00 00 00 00 00 00 00
```

## Contributing

Contributions are welcome! Areas for improvement:
- Add support for compressed saves
- Add batch processing for multiple saves
- Add interactive mode with date picker
- Add validation for game version compatibility
- Create GUI wrapper

## License

MIT License - Feel free to use, modify, and distribute as needed.

## Disclaimer

This tool modifies game save files. While it has been tested, there's always a risk of save corruption. **Always backup your saves first**. The author is not responsible for any loss of game progress or corrupted saves.

## Acknowledgments

- Piranha Games for creating MechWarrior 5: Mercenaries
- The MW5 modding community for save file format documentation

---

**Support**: For issues, feature requests, or contributions, please open an issue on GitHub.
