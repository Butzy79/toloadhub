# ToLoadHUB  

**ToLoadHUB** is a FlyWithLua plugin designed to manage passenger and cargo operations for ToLISS airplanes in X-Plane 12.  
This plugin streamlines the loading process, ensuring a realistic and balanced setup for your flights.  

## Features  
- **Passenger Management**: Configure and load passengers with ease.
- **Real-Time Loading**: Watch passengers being loaded into the aircraft in real-time for added immersion.
- **Cargo Management**: Simulate forward and aft cargo loading for a realistic experience.
- **Dynamic Loadsheet Generation**: Automatically calculates and generates a loadsheet for pre-flight checks.
- **Hoppie Integration**: Send the generated loadsheet directly to the avionics via Hoppie for enhanced workflow.
- **Seamless ToLISS Integration**: Built specifically for ToLISS aircraft, ensuring perfect compatibility.  

## Why Use ToLoadHUB?  
ToLoadHUB enhances your flight simulation experience by automating the often tedious process of managing passengers and cargo.
It adds immersion and professionalism to your flights, making every takeoff and landing more realistic.  

## Settings
ToLoadHUB provides a customizable configuration through the `toloadhub.ini` file, which is automatically created in the FlyWithLua scripts folder. Below are the available settings:  

### General Settings  
- **Auto Open ToLoad Hub Window**: Automatically opens the ToLoad Hub window upon simulator launch if the aircraft is compatible.  
- **Automatically Initialize Airplane**: Automatically sets the aircraft values to zero on simulator startup.  
- **Simulate Cargo**: If enabled, cargo loading/unloading is simulated; otherwise, it is loaded instantly.
- **Use Imperial Units**: Set Imperial units. SimBrief has priority over this value. If SimBrief plan is set to KGS, the units are metric. If SimBrief is set to POUNDS, the units are imperial.
- **Auto Start and Stop JD Ground Hanling**: If JD Ground Handling is installed, you can autostart it.
- **Debug Mode**: Enables or disables verbose debugging. Use only for troubleshooting.

### SimBrief Settings  
- **Username**: Your SimBrief username.
- **Auto Fetch at Beginning**: Automatically fetches data from SimBrief when the plugin loads.  
- **Randomize Passenger**: Simulates real passenger variations based on SimBrief data. For example, if SimBrief indicates 100 passengers, some may not board, or extra passengers may be simulated.  

### Hoppie Settings
- **Secret**: The password or secret received during registration at [hoppie.nl](https://www.hoppie.nl).
- **Enable Loadsheet**: Activates the sending of the loadsheet for display in the MCDU.  
  - The loadsheet is also visible in the **ATC MENU** under **MSG RECORD**.
- **Preliminary Loadsheet Only for Long-haul (+7hrs)**: Sends a preliminary loadsheet if a valid SimBrief plan exists, the flight number matches between SimBrief and the MCDU, and this option is enabled. The preliminary loadsheet can also be sent for all flights if not enabled.  
- **Loadsheet for chocks on and off**:  Sends a CPDLC message at FL100 with chocks-off and takeoff times, and another after you turn off your beacon and engines, including landing.

### Door Settings  
- **Close Doors after Boarding**: Automatically closes doors after boarding is completed.  
- **Close Doors after Deboarding**: Automatically closes doors after deboarding is completed.  
- **Auto Open Doors before Boarding**: Automatically opens doors for boarding if closed. You have the option to choose **No**, **Front Door Only**, or **All Doors**.  
- **Auto Open Doors before Deboarding**: Automatically opens doors for deboarding if closed. You have the option to choose **No**, **Front Door Only**, or **All Doors**.  

## Installation
1. Download the plugin files from this repository.  
2. Extract the contents to your FlyWithLua folder: 
<X-Plane 12>/Resources/plugins/FlyWithLua/
   - The file **toloadhub.lua** in Script goes into the Script directory, and the file **LIP.lua** in Modules goes into the Modules directory!
3. Launch X-Plane 12 and enjoy managing your load with ToLoadHUB.  

## Command to Set
In the settings, under **Controllers**, you can find a new command to assign to your key/button to open/close the ToLoad HUB window.  
The command name is `FlyWithLua -> TOLOADHUB -> Toggle ToLoadHub Window`.
You can assign a command to reset the window: `FlyWithLua -> TOLOADHUB -> Reset Position ToLoadHUB Window`

## Contributing  
Contributions are welcome! Feel free to submit pull requests or report issues to help improve the plugin.  

## License  
This project is licensed under the [MIT License](LICENSE).  

---

Take control of your flights with **ToLoadHUB**—your ultimate passenger and cargo management solution for ToLISS airplanes!
