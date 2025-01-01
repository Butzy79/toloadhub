--[[
    ToLoadHUB
    Author: Manta32
    Idea and by: @piotr-tomczyk aka @travisair  
    Special thanks to: @hotbso for the support
    Description:
    A FlyWithLua plugin for X-Plane 12 to manage passengers and loadsheet for ToLISS airplanes.
    Features include automatic loading from SimBrief, random passenger generation, and real-time loading.

    License: MIT License
--]]

-- == CONFIGURATION DEFAULT VARIABLES ==
local toLoadHub = {
    title = "ToLoadHUB",
    version = "1.0",
    file = "toloadhub.ini",
    visible_main = false,
    visible_settings = false,
    pax_count = 0, -- old intended_passenger
    max_passenger = 224,
    first_init = false,
    settings = {
        general = {
            debug = false,
            window_width = 800,
            window_height = 250,
            window_x = 200,
            window_y = 100,
            auto_open = true,
            auto_init = true
        },
        simbrief = {
            auto_fetch = true,
            randomize_passenger = true,
            username = ""
        },
        hoppie = {
            secret = "",
            enable_loadsheet = true
        },
        door = {
            simulate_cargo = false,
            close_boarding = true,
            close_deboarding = true
        }
    }
}

local toloadhub_window = nil
local toloadhub_window_settings = nil

local urls = {
    simbrief_fplan = "http://www.simbrief.com/api/xml.fetcher.php?username=" .. toLoadHub.settings.simbrief.username,
}
local LIP = require("LIP")
local http = require("socket.http")
local xml = require('LuaXml')
math.randomseed(os.time())

-- == Helper Functions ==
local function debug(stringToLog)
    if toLoadHub.settings.general.debug then
        logMsg(stringToLog)
    end
end

local function toBoolean(value)
    if type(value) == "string" then
        value = value:lower()
    end
    if value == "true" or value == true or value == 1 then
        return true
    end
    return false
end

-- == Utility Functions ==
local function saveSettingsToFile()
    debug(string.format("[%s] saveSettingsToFile()", toLoadHub.title))
    LIP.save(SCRIPT_DIRECTORY .. toLoadHub.file, toLoadHub.settings)
    debug(string.format("[%s] file saved", toLoadHub.title))
end

local function readSettingsToFile()
    local file, err = io.open(SCRIPT_DIRECTORY .. toLoadHub.file, 'r')
    if not file then return end
    local f = LIP.load(SCRIPT_DIRECTORY .. toLoadHub.file)
    if not f then return end
    for section, settings in pairs(f) do
        if toLoadHub.settings[section] then
            for key, value in pairs(settings) do
                if toLoadHub.settings[section][key] then
                    if type(toLoadHub.settings[section][key]) == 'boolean' then
                        toLoadHub.settings[section][key] = toBoolean(value)
                    elseif type(value) == 'number' then
                        toLoadHub.settings[section][key] = math.floor(value)
                    else
                        toLoadHub.settings[section][key] = value
                    end
                end
            end
        end
    end
end

local function fetchSimbriefFPlan()
    if toLoadHub.settings.simbrief.username == nil then
        debug(string.format("[%s] SimBrief username not set.", toLoadHub.title))
        return false
    end

    local response_xml, statusCode = http.request(urls.simbrief_fplan)
    if statusCode ~= 200 then
        debug(string.format("[%s] SimBrief API returned an error: [%d]", toLoadHub.title, statusCode))
        return false
    end

    local xml_data = xml.eval(response_xml)
    if not xml_data then
        debug(string.format("[%s] XML from SimBrief not valid.", toLoadHub.title))
        return false
    end

    local status = xml_data.OFP.fetch.status[1]
    if not status or status  ~= "Success" then
        debug(string.format("[%s] Simbrief Status not Success.", toLoadHub.title))
        return false
    end

    toLoadHub.pax_count = tonumber(xml_data.OFP.weights.pax_count[1])
    if toLoadHub.settings.simbrief.randomize_passenger then
        local r = 0.01 * math.random(92, 103)
	    toLoadHub.pax_count = math.floor(toLoadHub.pax_count * r)
        if toLoadHub.pax_count > toLoadHub.max_passenger then toLoadHub.pax_count = toLoadHub.max_passenger end
    end
    debug(string.format("[%s] SimBrief XML downloaded and parsed.", toLoadHub.title))
end

local function setAirplanePassengerNumber()
    if PLANE_ICAO == "A319" then
        toLoadHub.max_passenger = 145
    elseif PLANE_ICAO == "A321" or PLANE_ICAO == "A21N" then
        local a321EngineTypeIndex = dataref_table("AirbusFBW/EngineTypeIndex")
        if a321EngineTypeIndex[0] == 0 or a321EngineTypeIndex[0] == 1 then
            toLoadHub.max_passenger = 220
        else
            toLoadHub.max_passenger = 224
        end
    elseif PLANE_ICAO == "A20N" then
        toLoadHub.max_passenger = 188
    elseif PLANE_ICAO == "A339" then
        toLoadHub.max_passenger = 375
    elseif PLANE_ICAO == "A346" then
        toLoadHub.max_passenger = 440
    end
end

local function resetAirplaneParameters()
    toLoadHub_NoPax = 0
    toLoadHub_PaxDistrib = 0.5
    toLoadHub.pax_count = 0
    toLoadHub.first_init = true
    command_once("AirbusFBW/SetWeightAndCG")
    debug(string.format("[%s] Reset parameters done", toLoadHub.title))
end

-- == X-Plane Functions ==
function openToLoadHubWindow()
	toloadhub_window = float_wnd_create(toLoadHub.settings.general.window_width, toLoadHub.settings.general.window_height, 1, true)
    float_wnd_set_position(toloadhub_window, toLoadHub.settings.general.window_x, toLoadHub.settings.general.window_y)
	float_wnd_set_title(toloadhub_window, string.format("%s - v%s", toLoadHub.title, toLoadHub.version))
	float_wnd_set_imgui_builder(toloadhub_window, "viewToLoadHubWindow")
    float_wnd_set_onclose(toloadhub_window, "closeToLoadHubWindow")
    toLoadHub.visible_main = true
end

function openToLoadHubSettingsWindow()
	toloadhub_window_settings = float_wnd_create(400, 400, 1, true)
    float_wnd_set_position(toloadhub_window_settings, toLoadHub.settings.general.window_x, toLoadHub.settings.general.window_y)
	float_wnd_set_title(toloadhub_window_settings, string.format("%s Settings", toLoadHub.title))
	float_wnd_set_imgui_builder(toloadhub_window_settings, "viewToLoadHubWindowSettings")
    float_wnd_set_onclose(toloadhub_window_settings, "closeToLoadHubSettingsWindow")
    toLoadHub.visible_main = true
end

function closeToLoadHubWindow()
    if toLoadHub.visible_settings then
        float_wnd_destroy(toloadhub_window_settings)
    end
    toLoadHub.visible_main = false
    toLoadHub.visible_settings = false
end

function closeToLoadHubSettingsWindow()
    toLoadHub.visible_settings = false
end


function viewToLoadHubWindow()
    if not toLoadHub.first_init then -- Not auto init, and plane not set to zero: RETURN
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
        imgui.TextUnformatted("ToLoadHUB not auto initiated, please initiate.")
        imgui.PopStyleColor()
        if imgui.Button("Init", 100, 30) then
            resetAirplaneParameters()
        end
        return
    end

    if not toLoadHub.visible_settings then
        imgui.Separator()
        if imgui.Button("Settings", 100, 30) then

        end
    end
    -- AirbusFBW/AftCargo
    -- AirbusFBW/FwdCargo
    -- ZWF = toliss_airbus/iscsinterface/blockZfw
    -- ZWF Applied = toliss_airbus/iscsinterface/zfw
    -- GWCG = toliss_airbus/iscsinterface/currentCG
    -- ZWFCG = toliss_airbus/iscsinterface/blockZfwCG
    -- ZWFCG Applied = toliss_airbus/iscsinterface/zfwCG
    -- FUEL Block TO apply = toliss_airbus/iscsinterface/setNewBlockFuel

end

function viewToLoadHubWindowSettings()
-- General Settings
    imgui.PushStyleColor(imgui.constant.Col.Text, 0xFFA500FF) -- Colore arancione
    imgui.TextUnformatted("General Settings:")
    imgui.PopStyleColor()

    local changed, newval
    changed, newval = imgui.Checkbox("Auto Open ToLoad Hub Window", toLoadHub.settings.general.auto_open)
    if changed then toLoadHub.settings.general.auto_open = newval end

    changed, newval = imgui.Checkbox("Automatically initialize airplane with zero", toLoadHub.settings.general.auto_init)
    if changed then toLoadHub.settings.general.auto_init = newval end

    changed, newval = imgui.Checkbox("Debug Mode", toLoadHub.settings.general.debug)
    if changed then toLoadHub.settings.general.debug = newval end
    imgui.Spacing()

    -- SimBrief Settings
    imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
    imgui.TextUnformatted("SimBrief Settings:")
    imgui.PopStyleColor()

    changed, newval = imgui.Checkbox("Auto Fetch at beginning", toLoadHub.settings.simbrief.auto_fetch)
    if changed then toLoadHub.settings.simbrief.auto_fetch = newval end

    changed, newval = imgui.Checkbox("Randomize Passenger", toLoadHub.settings.simbrief.randomize_passenger)
    if changed then toLoadHub.settings.simbrief.randomize_passenger = newval end

    imgui.Text("Username:")
    changed, newval = imgui.InputText("##username", toLoadHub.settings.simbrief.username or "", 128)
    if changed then toLoadHub.settings.simbrief.username = newval end

    imgui.Spacing()

    -- Hoppie Settings
    imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF6A5ACD)
    imgui.TextUnformatted("Hoppie Settings:")
    imgui.PopStyleColor()

    changed, newval = imgui.Checkbox("Enable Loadsheet", toLoadHub.settings.hoppie.enable_loadsheet)
    if changed then toLoadHub.settings.hoppie.enable_loadsheet = newval end

    imgui.Text("Secret:")
    changed, newval = imgui.InputText("##secret", toLoadHub.settings.hoppie.secret or "", 128)
    if changed then toLoadHub.settings.hoppie.secret = newval end

    imgui.Spacing()

    -- Door Settings
    imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF32CD32)
    imgui.TextUnformatted("Door Settings:")
    imgui.PopStyleColor()

    changed, newval = imgui.Checkbox("Simulate Cargo", toLoadHub.settings.door.simulate_cargo)
    if changed then toLoadHub.settings.door.simulate_cargo = newval end

    changed, newval = imgui.Checkbox("Close Doors on Boarding", settings.door.close_boarding)
    if changed then toLoadHub.settings.door.close_boarding = newval end

    changed, newval = imgui.Checkbox("Close Doors on Deboarding", settings.door.close_deboarding)
    if changed then toLoadHub.settings.door.close_deboarding = newval end
end

local function toggleToloadHubWindow(onlyOpen)
    if not onlyOpen then
        if toLoadHub.visible_main then
            float_wnd_destroy(toloadhub_window)
        end
        if toLoadHub.visible_settings then
            float_wnd_destroy(toloadhub_window_settings)
        end
        if toLoadHub.visible_main or toLoadHub.visible_settings then
            toLoadHub.visible_main = false
            toLoadHub.visible_settings = false
            return
        end
    end

    if not toLoadHub.visible_main then
        openToLoadHubWindow()
    end
end

-- == Main code ==
if PLANE_ICAO == "A319" or PLANE_ICAO == "A20N" or PLANE_ICAO == "A321" or
   PLANE_ICAO == "A21N" or PLANE_ICAO == "A346" or PLANE_ICAO == "A339"
then
    debug(string.format("[%s] Version %s initialized.", toLoadHub.title, toLoadHub.version))
    dataref("toLoadHub_NoPax", "AirbusFBW/NoPax", "writeable")
    dataref("toLoadHub_PaxDistrib", "AirbusFBW/PaxDistrib", "writeable")
    setAirplanePassengerNumber()
    readSettingsToFile()
    if toLoadHub.settings.simbrief.auto_fetch then
        fetchSimbriefFPlan()
    end
    if toLoadHub.settings.general.auto_init then
        resetAirplaneParameters()
    end
    add_macro("ToLoad Hub", "toggleToloadHubWindow(true)")
    create_command("FlyWithLua/TOLOADHUB/Toggle_toloadhub", "Togle ToLoadHUB window", "toggleToloadHubWindow(false)", "", "")

    if toLoadHub.settings.general.auto_open then
       toggleToloadHubWindow(true)
    end
    do_on_exit("saveSettingsToFile()")
    debug(string.format("[%s] Plugin fully loaded.", toLoadHub.title))
end
