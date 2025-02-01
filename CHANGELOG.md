# Changelog  

All notable changes to this project will be documented in this file.  
The format is based on [Keep a Changelog](https://keepachangelog.com/),  
and this project adheres to [Semantic Versioning](https://semver.org/).
## [1.1.0]- 2025-01-18
### Added
- Fuel Management
- Jetway auto connection

### Fix
- Pounds value fixed for cargo
- Release Flight No once Chock Off Sent

## [1.0.1]- 2025-01-18
### Fix
- A321 XLR values

## [1.0.0]- 2025-01-18
### First stable release
### Added
- Loadsheet pax value
- Cargo time trimmed
- Fuel saved/burned improved
- Shortcut command to start board and deboard
- Setting to start loading cargo. Passengers require an action to start boarding.
## [0.14.0]- 2025-01-13
### Added
- Arrival times loadsheet with fuel status
- In settings, you can now enable simultaneous cargo loading with passenger boarding.

## [0.13.0]- 2025-01-12
### Added
- Time is shown in local time by default. You can set it to UTC in the Hoppie settings section.
### Bugfix
- The estimated time is now more accurate.

## [0.12.2]- 2025-01-10
### Added
- Airstair / Jetbridge selection on boarding/deboarding
- CPDLC Message for Chocks Off and Chocks On

### Bugfix
- ZFWCG wrong dataref set
- Settings Menu macOS fixed

## [0.11.0]- 2025-01-08
### Added
- Imperial or Metric management is determined by SimBrief or the app itself, with SimBrief taking priority.

### Bugfix
- Cargo time not correct
- Issues with Secret and SimBriefID

## [0.10.3.1] - 2025-01-07
### Bugfix
- simbriefID null value

## [0.10.3] - 2025-01-07
### Fixed
- Changed the cargo performances
- Window focus popup all time

## [0.10.2] - 2025-01-06
### Added
- **Reset Window** option in the **top bar menu** under **FlyWithLua -> FlyWithLuaMacros -> ToLoadHUB** (resets the window to its original position).
- Enabled the ability to assign a command in control settings: **FlyWithLua -> TOLOADHUB -> Reset Position ToLoadHUB Window**.
- Default Boarding/Deboarding speed saved
- First draft for JD Ground Handling
### Fixed
- Bugfix on VR view
- Dataref for not a320neo

## [0.10.1] - 2025-01-05
### Fixed
- Bugfix for slow refueling

## [0.10.0] - 2025-01-04
### Added
- Preliminary loadsheet
- Auto Door for Boarding or Deboarding

## [0.9.0] - 2025-01-04
### Added
- Cargo Door automation

## [0.8.0] - 2025-01-03
### Fixed
- VR Fixing

## [0.5.1] - 2025-01-03
### Fixed
- Wording change

## [0.5.0] - 2025-01-03
### Fixed
- New logic for activate weight and balance

## [0.2.3] - 2025-01-03
### Fixed
- Detached DataRef to ToLoadHUB Logic

## [0.2.2] - 2025-01-03
### Fixed
- Fuel Block wrong set

## [0.2.1] - 2025-01-03
### Fixed
- Cargo value from freight_added in SimBrief

## [0.2.0] - 2025-01-02
### Added
- Initial release of ToLoadHUB.  
- Passenger management with real-time loading.  
- Dynamic loadsheet generation.  
- Basic SimBrief and ToLISS integration.  
