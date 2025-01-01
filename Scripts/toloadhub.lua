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
local valid_plane_icao = { A319 = true, A20N = true, A321 = true, A21N = true, A346 = true, A339 = true }
if not valid_plane_icao[PLANE_ICAO] then
    XPLMSpeakString("Invalid Airplane for the ToLoad Hub Plugin")
    return
end

-- == CONFIGURATION DEFAULT VARIABLES ==
local toLoadHub = {
    title = "ToLoadHUB",
    version = "1.0.0",
    file = "toloadhub.ini",
    visible_main = false,
    visible_settings = false,
    pax_count = 0, -- old intended_passenger
    max_passenger = 224,
    first_init = false,
    settings = {
        general = {
            debug = false,
            window_width = 375,
            window_height = 400,
            window_x = 160,
            window_y = 200,
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
function saveSettingsToFile(final)
    debug(string.format("[%s] saveSettingsToFile(%s)", toLoadHub.title, tostring(final)))
    if final or not final then
        local wLeft, wTop, wRight, wBottom = float_wnd_get_geometry(toloadhub_window)
        local scrLeft, scrTop, scrRight, scrBottom = XPLMGetScreenBoundsGlobal()
        toLoadHub.settings.general.window_x = wLeft - scrLeft
        toLoadHub.settings.general.window_y = wBottom - scrBottom
    end

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
function openToLoadHubWindow(isNew)
    if isNew then
        toloadhub_window = float_wnd_create(toLoadHub.settings.general.window_width, toLoadHub.settings.general.window_height, 1, true)
        float_wnd_set_position(toloadhub_window, toLoadHub.settings.general.window_x, toLoadHub.settings.general.window_y)
    end
    float_wnd_set_title(toloadhub_window, string.format("%s - v%s", toLoadHub.title, toLoadHub.version))
    float_wnd_set_imgui_builder(toloadhub_window, "viewToLoadHubWindow")
    float_wnd_set_onclose(toloadhub_window, "closeToLoadHubWindow")
    toLoadHub.visible_main = true
end

function openToLoadHubSettingsWindow()
    float_wnd_set_title(toloadhub_window, string.format("%s - Settings", toLoadHub.title))
    float_wnd_set_imgui_builder(toloadhub_window, "viewToLoadHubWindowSettings")
    float_wnd_set_onclose(toloadhub_window, "closeToLoadHubWindow")
    toLoadHub.visible_main = true
end

function closeToLoadHubWindow()
    saveSettingsToFile(true)
    toLoadHub.visible_main = false
    toLoadHub.visible_settings = false
end


function viewToLoadHubWindow()
    local wLeft, wTop, wRight, wBottom = float_wnd_get_geometry(toloadhub_window)
    toLoadHub.settings.general.window_height = wTop - wBottom
    toLoadHub.settings.general.window_width = wRight - wLeft
    
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
        imgui.Spacing()
        imgui.SameLine((toLoadHub.settings.general.window_width)-125)
        if imgui.Button("Settings", 100, 30) then
            toLoadHub.visible_settings = true
            toLoadHub.visible_main = false
            openToLoadHubSettingsWindow()
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
    local wLeft, wTop, wRight, wBottom = float_wnd_get_geometry(toloadhub_window)
    toLoadHub.settings.general.window_height = wTop - wBottom
    toLoadHub.settings.general.window_width = wRight - wLeft

    imgui.SameLine((toLoadHub.settings.general.window_width/2)-75)
    if imgui.Button("Back to ToLoad HUB", 140, 30) then
        toLoadHub.visible_settings = false
        toLoadHub.visible_main = true
        openToLoadHubWindow(false)
    end
    local setSave = false
    imgui.Separator()
    imgui.Spacing()

    -- General Settings
    imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8) -- Colore arancione
    imgui.TextUnformatted("General Settings:")
    imgui.PopStyleColor()

    local changed, newval
    changed, newval = imgui.Checkbox("Auto Open ToLoad Hub Window", toLoadHub.settings.general.auto_open)
    if changed then toLoadHub.settings.general.auto_open , setSave = newval, true end

    changed, newval = imgui.Checkbox("Automatically initialize airplane", toLoadHub.settings.general.auto_init)
    if changed then toLoadHub.settings.general.auto_init , setSave = newval, true end

    changed, newval = imgui.Checkbox("Debug Mode", toLoadHub.settings.general.debug)
    if changed then toLoadHub.settings.general.debug , setSave = newval, true end
    imgui.Separator()
    imgui.Spacing()

    -- SimBrief Settings
    imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
    imgui.TextUnformatted("SimBrief Settings:")
    imgui.PopStyleColor()

    changed, newval = imgui.Checkbox("Auto Fetch at beginning", toLoadHub.settings.simbrief.auto_fetch)
    if changed then toLoadHub.settings.simbrief.auto_fetch , setSave = newval, true end

    changed, newval = imgui.Checkbox("Randomize Passenger", toLoadHub.settings.simbrief.randomize_passenger)
    if changed then toLoadHub.settings.simbrief.randomize_passenger , setSave = newval, true end
    
    imgui.TextUnformatted("Username:")
    imgui.SameLine(75)
    changed, newval = imgui.InputText("##username", toLoadHub.settings.simbrief.username, 50)
    if changed then toLoadHub.settings.simbrief.username , setSave = newval, true end
    imgui.Separator()
    imgui.Spacing()

    -- Hoppie Settings
    imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
    imgui.TextUnformatted("Hoppie Settings:")
    imgui.PopStyleColor()

    changed, newval = imgui.Checkbox("Enable Loadsheet", toLoadHub.settings.hoppie.enable_loadsheet)
    if changed then toLoadHub.settings.hoppie.enable_loadsheet , setSave = newval, true end

    imgui.TextUnformatted("Secret:")
    imgui.SameLine(75)
    changed, newval = imgui.InputText("##secret", toLoadHub.settings.hoppie.secret, 80)
    if changed then toLoadHub.settings.hoppie.secret , setSave = newval, true end
    imgui.Separator()
    imgui.Spacing()

    -- Door Settings
    imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
    imgui.TextUnformatted("Door Settings:")
    imgui.PopStyleColor()

    changed, newval = imgui.Checkbox("Simulate Cargo", toLoadHub.settings.door.simulate_cargo)
    if changed then toLoadHub.settings.door.simulate_cargo , setSave = newval, true end

    changed, newval = imgui.Checkbox("Close Doors on Boarding", toLoadHub.settings.door.close_boarding)
    if changed then toLoadHub.settings.door.close_boarding , setSave = newval, true end

    changed, newval = imgui.Checkbox("Close Doors on Deboarding", toLoadHub.settings.door.close_deboarding)
    if changed then toLoadHub.settings.door.close_deboarding , setSave = newval, true end

    if setSave then
        saveSettingsToFile(false)
        setSave = false
    end
end

function loadToloadHubWindow()
    if not toLoadHub.visible_main then
        openToLoadHubWindow(true)
    end
end

function toggleToloadHubWindow()
    if toLoadHub.visible_main or toLoadHub.visible_settings then
        float_wnd_destroy(toloadhub_window)
        return
    end
    loadToloadHubWindow()
end

-- == Main code ==
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
add_macro("ToLoad Hub", "loadToloadHubWindow()")
create_command("FlyWithLua/TOLOADHUB/Toggle_toloadhub", "Togle ToLoadHUB window", "toggleToloadHubWindow()", "", "")

if toLoadHub.settings.general.auto_open then
    loadToloadHubWindow()
end
do_on_exit("saveSettingsToFile(true)")
debug(string.format("[%s] Plugin fully loaded.", toLoadHub.title))
