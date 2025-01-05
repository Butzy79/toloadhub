--[[
    ToLoadHUB
    Author: Manta32
    Special thanks to: Giulio Cataldo for the night spent suffering with me
    Initial project by: @piotr-tomczyk aka @travisair
    Thanks to: @hotbso for the idea
    Extra thanks to: @Qlaudie73 for the new features, and @Pilot4XP for the valuable information
    Description:
    A FlyWithLua plugin for X-Plane 12 to manage passengers and loadsheet for ToLISS airplanes.
    Features include automatic loading from SimBrief, random passenger generation, and real-time loading.

    TODO: Missing max Fuel and Cargo for A339 and A346
    License: MIT License
--]]

---@diagnostic disable: undefined-global
local valid_plane_icao = { A319 = true, A20N = true, A321 = true, A21N = true, A346 = true, A339 = true }
if not valid_plane_icao[PLANE_ICAO] then
    XPLMSpeakString("Invalid Airplane for the ToLoad Hub Plugin")
    return
end

-- == CONFIGURATION DEFAULT VARIABLES ==
local toLoadHub = {
    title = "ToLoadHUB",
    version = "0.10.2",
    file = "toloadhub.ini",
    visible_main = false,
    visible_settings = false,
    pax_count = 0, -- old intendedPassengerNumber
    max_passenger = 224,
    max_cargo_fwd = 3000,
    max_cargo_aft = 5000,
    max_fuel = 20000,
    cargo = 0,
    cargo_aft = 0,
    cargo_fwd = 0,
    pax_distribution_range = {35, 60},
    cargo_fwd_distribution_range = {55, 75},
    cargo_starting_range = {45, 60},
    cargo_speeds = {0, 3, 6},
    kgPerUnit = 50,
    first_init = false,
    phases = {
        is_onboarding = false,
        is_pax_onboarded = false,
        is_pax_deboarded = false,
        is_cargo_started = false,
        is_cargo_onboarded = false,
        is_cargo_deboarded = false,
        is_onboarding_pause = false,
        is_onboarded = false,
        is_deboarding = false,
        is_deboarding_pause = false,
        is_deboarded = false,
    },
    boarding_speed = 0,
    boarding_secnds_per_pax = 0,
    next_boarding_check = os.time(), -- old nextTimeBoardingCheck
    next_cargo_check = os.time(),
    wait_until_speak = os.time(),
    setWeightTime = os.time(),
    what_to_speak = nil,
    boarding_sound_played = false,
    deboarding_sound_played = false,
    boarding_cargo_sound_played = false,
    deboarding_cargo_sound_played = false,
    setWeightCommand = false,
    full_deboard_sound = false,
    hoppie = {
        loadsheet_sent = false,
        loadsheet_sending = false,
        loadsheet_preliminary_ready = false,
        loadsheet_preliminary_sent = false,
        loadsheet_check = os.time(),
    },
    simbrief = {
        est_block = nil,
        callsign = nil,
        plan_ramp = nil,
        cargo = nil,
        pax_count = nil,
        est_zfw = nil,
    },
    settings = {
        general = {
            debug = false,
            window_width = 400,
            window_height = 250,
            window_x = 160,
            window_y = 200,
            auto_open = true,
            auto_init = true,
            simulate_cargo = true,
            boarding_speed = 0,
        },
        simbrief = {
            auto_fetch = true,
            randomize_passenger = true,
        },
        hoppie = {
            enable_loadsheet = true,
            preliminary_loadsheet = false
        },
        door = {
            close_boarding = true,
            close_deboarding = true,
            open_boarding = 0,
            open_deboarding = 0
        }
    }
}

local loadsheetStructure = {
    new = function(self)
        local obj = {
            isFinal = false,
            warning = "",
            labelText = "",
            flt_no = "",
            zfw = "",
            zfwcg = "",
            gwcg = "",
            f_blk = ""
        }
        setmetatable(obj, self)
        self.__index = self
        return obj
    end
}

local toloadhub_window = nil

local urls = {
    simbrief_fplan = "http://www.simbrief.com/api/xml.fetcher.php?userid=",
    hoppie_connect = "https://www.hoppie.nl/acars/system/connect.html"
}
local LIP = require("LIP")
local http = require("socket.http")
local ltn12 = require("ltn12")

local toLoadHub_NoPax = 0
local toLoadHub_AftCargo = 0
local toLoadHub_FwdCargo = 0
local toLoadHub_PaxDistrib = 0.5

if not SUPPORTS_FLOATING_WINDOWS then
    -- to make sure the script doesn't stop old FlyWithLua versions
    logMsg("imgui not supported by your FlyWithLua version")
    return
end

require("LuaXml")

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

local function calculateTimeWithCargo(a, b)
    local res = a / 2 + b
    return (res < a and a) or (res < b and b) or res
end

-- == Utility Functions ==
function saveSettingsToFileToLoadHub(final)
    debug(string.format("[%s] saveSettingsToFileToLoadHub(%s)", toLoadHub.title, tostring(final)))
    if final and (toLoadHub.visible_settings or toLoadHub.visible_main) and not float_wnd_is_vr(toloadhub_window) then
        local wLeft, wTop, wRight, wBottom = float_wnd_get_geometry(toloadhub_window)
        local scrLeft, scrTop, scrRight, scrBottom = XPLMGetScreenBoundsGlobal()
        toLoadHub.settings.general.window_x = math.max(scrLeft, wLeft - scrLeft)
        toLoadHub.settings.general.window_y = math.max(scrBottom, wBottom - scrBottom)
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
                if toLoadHub.settings[section][key] ~= nil then
                    if type(toLoadHub.settings[section][key]) == 'boolean' then
                        toLoadHub.settings[section][key] = toBoolean(value)
                    elseif type(toLoadHub.settings[section][key]) == 'number' then
                        toLoadHub.settings[section][key] = math.floor(value)
                    else
                        toLoadHub.settings[section][key] = value
                    end
                end
            end
        end
    end
end

local function divideCargoFwdAft()
    local randomPercentage = math.random(toLoadHub.cargo_fwd_distribution_range[1], toLoadHub.cargo_fwd_distribution_range[2]) / 100
    -- Calculate forward and aft cargo
    toLoadHub.cargo_fwd = toLoadHub.cargo * randomPercentage
    toLoadHub.cargo_aft = toLoadHub.cargo - toLoadHub.cargo_fwd
end

local function fetchSimbriefFPlan()
    if not toLoadHub_simBriefID or toLoadHub_simBriefID == nil or not toLoadHub_simBriefID:gsub("^%s*(.-)%s*$", "%1") then
        debug(string.format("[%s] SimBrief username not set.", toLoadHub.title))
        return false
    end
    local response_xml, statusCode = http.request(urls.simbrief_fplan .. toLoadHub_simBriefID)

    if statusCode ~= 200 then
        debug(string.format("[%s] SimBrief API returned an error: [%d]", toLoadHub.title, statusCode))
        return false
    end

    local xml_data = xml.eval(response_xml)
    if not xml_data then
        debug(string.format("[%s] XML from SimBrief not valid.", toLoadHub.title))
        return false
    end
    local status = xml_data:find("status")
    if not status or status[1]  ~= "Success" then
        debug(string.format("[%s] Simbrief Status not Success.", toLoadHub.title))
        return false
    end
    local pax_count = xml_data:find("pax_count")
    toLoadHub.pax_count = tonumber(pax_count[1])
    toLoadHub.simbrief.pax_count = toLoadHub.pax_count

    if toLoadHub.settings.simbrief.randomize_passenger then
        local r = 0.01 * math.random(92, 103)
        toLoadHub.pax_count = math.floor(toLoadHub.pax_count * r)
        if toLoadHub.pax_count > toLoadHub.max_passenger then toLoadHub.pax_count = toLoadHub.max_passenger end
    end

    local freight_added = xml_data:find("freight_added")
    toLoadHub.cargo = tonumber(freight_added[1])

    local plan_ramp = xml_data:find("plan_ramp")
    toLoadHub.simbrief.plan_ramp = tonumber(plan_ramp[1])

    local callsign = xml_data:find("callsign")
    toLoadHub.simbrief.callsign = callsign[1]

    local est_block = xml_data:find("est_block")
    toLoadHub.simbrief.est_block = tonumber(est_block[1])

    local est_zfw = xml_data:find("est_zfw")
    toLoadHub.simbrief.est_zfw = tonumber(est_zfw[1])

    toLoadHub.simbrief.cargo = toLoadHub.cargo
    
    debug(string.format("[%s] SimBrief XML downloaded and parsed.", toLoadHub.title))
end

local function setIscsTemporarySimbrief()
    toLoadHub_NoPax_XP = toLoadHub.simbrief.pax_count
    toLoadHub_AftCargo_XP = toLoadHub.cargo_aft
    toLoadHub_FwdCargo_XP = toLoadHub.cargo_fwd
end

local function setAirplaneNumbers()
    if PLANE_ICAO == "A319" then
        toLoadHub.max_passenger = 145
        toLoadHub.max_cargo_fwd = 2268
        toLoadHub.max_cargo_aft = 4518
        toLoadHub.max_fuel = 18728
    elseif PLANE_ICAO == "A321" or PLANE_ICAO == "A21N" then
        local a321EngineTypeIndex = dataref_table("AirbusFBW/EngineTypeIndex")
        toLoadHub.max_cargo_fwd = 5670
        toLoadHub.max_cargo_aft = 7167
        toLoadHub.max_fuel = 23207
        if a321EngineTypeIndex[0] == 0 or a321EngineTypeIndex[0] == 1 then
            toLoadHub.max_passenger = 220
        else
            toLoadHub.max_passenger = 224
        end
    elseif PLANE_ICAO == "A20N" then
        toLoadHub.max_passenger = 188
        toLoadHub.max_cargo_fwd = 3402
        toLoadHub.max_cargo_aft = 6033
        toLoadHub.max_fuel = 18623
    elseif PLANE_ICAO == "A339" then
        toLoadHub.max_passenger = 375
    elseif PLANE_ICAO == "A346" then
        toLoadHub.max_passenger = 440
    end
end

local function resetAirplaneParameters()
    toLoadHub_NoPax = 0
    toLoadHub_AftCargo = 0
    toLoadHub_FwdCargo = 0
    toLoadHub_PaxDistrib = 0.5

    toLoadHub.pax_count = 0
    toLoadHub.cargo = 0
    toLoadHub.cargo_aft = 0
    toLoadHub.cargo_fwd = 0
    toLoadHub.boarding_secnds_per_pax = 0
    toLoadHub.boarding_secnds_per_cargo_unit = 0
    toLoadHub.next_boarding_check = os.time()
    toLoadHub.next_cargo_check = os.time()
    toLoadHub.wait_until_speak = os.time()
    toLoadHub.setWeightTime = os.time()
    toLoadHub.what_to_speak = nil
    toLoadHub.boarding_sound_played = false
    toLoadHub.deboarding_sound_played = false
    toLoadHub.boarding_cargo_sound_played = false
    toLoadHub.deboarding_cargo_sound_played = false
    toLoadHub.full_deboard_sound = false
    for key in pairs(toLoadHub.hoppie) do
        if key == "loadsheet_check" then
            toLoadHub.hoppie[key] = os.time()
        else
            toLoadHub.hoppie[key] = false
        end
    end
    toLoadHub.setWeightCommand = false
    for key in pairs(toLoadHub.phases) do
        toLoadHub.phases[key] = false
    end
    for key in pairs(toLoadHub.simbrief) do
        toLoadHub.simbrief[key] = nil
    end
    if not toLoadHub.first_init and toLoadHub.settings.simbrief.auto_fetch then
        fetchSimbriefFPlan()
    end
    toLoadHub.first_init = true
    toLoadHub_NoPax_XP = 0
    toLoadHub_AftCargo_XP = 0
    toLoadHub_FwdCargo_XP = 0
    toLoadHub_PaxDistrib_XP = 0.5
    command_once("AirbusFBW/SetWeightAndCG")

    debug(string.format("[%s] Reset parameters done", toLoadHub.title))
end

local function registerSetWeight()
    if not toLoadHub.setWeightCommand or toLoadHub.setWeightTime > os.time() then return end
    command_once("AirbusFBW/SetWeightAndCG")
    toLoadHub.setWeightCommand = false
end

local function setRandomNumberOfPassengers()
    local passengerDistributionGroup = math.random(0, 100)
    local ranges = {
        {2, 0.22, 0.54},
        {16, 0.54, 0.72},
        {58, 0.72, 0.87},
        {100, 0.87, 1.0} -- 1.0 = 100%
    }
    for _, range in ipairs(ranges) do
        if passengerDistributionGroup < range[1] then
            toLoadHub.pax_count = math.random(
                math.floor(toLoadHub.max_passenger * range[2]),
                math.floor(toLoadHub.max_passenger * range[3])
            )
            return
        end
    end
end

local function playChimeSound()
    if toLoadHub.what_to_speak then return end
    if toLoadHub.phases.is_pax_onboarded and not toLoadHub.phases.is_pax_deboarded then
        if toLoadHub.pax_count > 0 then
            command_once( "AirbusFBW/CheckCabin" )
            toLoadHub.what_to_speak = "Boarding Passenger Completed"
            toLoadHub.wait_until_speak = os.time() + 2
        end
        toLoadHub.boarding_sound_played = true
    end
    if toLoadHub.phases.is_pax_deboarded then
        if toLoadHub.pax_count > 0 then
            command_once( "AirbusFBW/CheckCabin" )
            toLoadHub.what_to_speak = "Deboarding Passenger Completed"
            toLoadHub.wait_until_speak = os.time() + 2
        end
        toLoadHub.deboarding_sound_played = true
    end
end

local function playCargoSound()
    if toLoadHub.what_to_speak then return end
    if toLoadHub.phases.is_cargo_onboarded and not toLoadHub.phases.is_cargo_deboarded then
        if toLoadHub.cargo > 0 then
            toLoadHub.what_to_speak = "Cargo Loading Completed"
            toLoadHub.wait_until_speak = os.time() + 2
        end
        toLoadHub.boarding_cargo_sound_played = true
    end
    if toLoadHub.phases.is_cargo_deboarded then
        if toLoadHub.cargo > 0 then
            toLoadHub.what_to_speak = "Cargo offloading Completed"
            toLoadHub.wait_until_speak = os.time() + 2
        end
        toLoadHub.deboarding_cargo_sound_played = true
    end
end

local function playFinalSound()
    if toLoadHub.what_to_speak then return end
    if toLoadHub.cargo > 0 and toLoadHub.pax_count > 0 then
        toLoadHub.what_to_speak = "Flight completed, all passengers and cargo have been deboarded."
        toLoadHub.wait_until_speak = os.time() + 2
    end
    toLoadHub.full_deboard_sound = true
end

local function openDoors(boarding)
    local setVal = boarding and toLoadHub.settings.door.open_boarding or toLoadHub.settings.door.open_deboarding
    if setVal <= 0 then return end
    toLoadHub_Doors_1 = 2
    if setVal > 1 then
        toLoadHub_Doors_2 = 2
        if PLANE_ICAO == "A321" or PLANE_ICAO == "A21N" or PLANE_ICAO == "A346" or PLANE_ICAO == "A339" then
            toLoadHub_Doors_6 = 2
        end
    end
end

local function closeDoors(boarding)
    if not toLoadHub.settings.door.close_boarding and boarding then return end
    if not toLoadHub.settings.door.close_deboarding and not boarding then return end

    toLoadHub_Doors_1 = 0
    toLoadHub_Doors_2 = 0
    if PLANE_ICAO == "A321" or PLANE_ICAO == "A21N" or PLANE_ICAO == "A346" or PLANE_ICAO == "A339" then
        toLoadHub_Doors_6 = 0
    end
end

local function closeDoorsCargo()
    toLoadHub_CargoDoors_1 = 0
    toLoadHub_CargoDoors_2 = 0
end

local function openDoorsCargo()
    toLoadHub_CargoDoors_1 = 2
    toLoadHub_CargoDoors_2 = 2
end

local function focusOnToLoadHub()
    if not toLoadHub.visible_main and not toLoadHub.visible_settings then
        openToLoadHubWindow(true)
    elseif not toLoadHub.visible_main and toLoadHub.visible_settings then
        toLoadHub.visible_settings = false
        toLoadHub.visible_main = true
        openToLoadHubWindow(false)
    end
end

local function isNoPaxInRangeForCargo()
    return toLoadHub_NoPax >= toLoadHub.pax_count * (math.random(toLoadHub.cargo_starting_range[1], toLoadHub.cargo_starting_range[2]) / 100)
end

local function addingCargoFwdAft()
    local someChanges = false
    if toLoadHub_AftCargo < toLoadHub.cargo_aft then
        toLoadHub_AftCargo = math.min(toLoadHub_AftCargo + toLoadHub.kgPerUnit, toLoadHub.cargo_aft)
        someChanges = true
    end
    if toLoadHub_FwdCargo < toLoadHub.cargo_fwd then
        toLoadHub_FwdCargo = math.min(toLoadHub_FwdCargo + toLoadHub.kgPerUnit, toLoadHub.cargo_fwd)
        someChanges = true
    end
    return someChanges
end

local function removingCargoFwdAft()
    local someChanges = false
    if toLoadHub_AftCargo > 0 then
        toLoadHub_AftCargo = math.max(toLoadHub_AftCargo - toLoadHub.kgPerUnit, 0)
        someChanges = true
    end
    if toLoadHub_FwdCargo > 0 then
        toLoadHub_FwdCargo = math.max(toLoadHub_FwdCargo - toLoadHub.kgPerUnit, 0)
        someChanges = true
    end
    return someChanges
end

local function formatRowLoadSheet(label, value, digit)
    return label .. string.rep(".", digit - #label - #tostring(value)) .. tostring(" @" .. value .. "@ ")
end

local function sendLoadsheetToToliss(data)
    if not getmetatable(data) == loadsheetStructure then return end
    if toLoadHub.hoppie.loadsheet_check > os.time() or toLoadHub.hoppie.loadsheet_sending then return end
    debug(string.format("[%s] Starting Loadsheet %s composition.", toLoadHub.title, data.labelText))

    if not toLoadHub_hoppieLogon or toLoadHub_hoppieLogon == nil or not toLoadHub_hoppieLogon:gsub("^%s*(.-)%s*$", "%1") then
        debug(string.format("[%s] Hoppie secret not set.", toLoadHub.title))
        return false
    end
    toLoadHub.hoppie.loadsheet_sending = true

    local loadSheetContent = "/data2/313//NE/" .. table.concat({
        "Loadsheet " .. data.labelText .. " " .. os.date("%H:%M"),
        formatRowLoadSheet("ZFW",  data.zfw, 9),
        formatRowLoadSheet("ZFWCG", data.zfwcg, 9),
        formatRowLoadSheet("GWCG", data.gwcg, 9),
        formatRowLoadSheet("F.BLK", data.f_blk, 9),
    }, "\n")
    if data.warning ~= "" then
        loadSheetContent = loadSheetContent .. "\n" .. formatRowLoadSheet("@WARN!@ F.BLK EXP.", data.warning, 22)
    end

    debug(string.format("[%s] Hoppie flt_no %s.", toLoadHub.title, tostring(data.flt_no)))

    local payload = string.format("logon=%s&from=%s&to=%s&type=%s&packet=%s",
        toLoadHub_hoppieLogon,
        toLoadHub.title,
        data.flt_no,
        'cpdlc', 
        loadSheetContent:gsub("\n", "%%0A")
    )


    local _, code = http.request{
        url = urls.hoppie_connect,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Content-Length"] = tostring(#payload),
        },
        source = ltn12.source.string(payload),
    }
    debug(string.format("[%s] Hoppie returning code %s.", toLoadHub.title, tostring(code)))
    if code == 200 and data.isFinal then toLoadHub.hoppie.loadsheet_sent = true end
    if code == 200 and not data.isFinal then toLoadHub.hoppie.loadsheet_preliminary_sent = true end
    toLoadHub.hoppie.loadsheet_sending = false
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
    saveSettingsToFileToLoadHub(true)
    toLoadHub.visible_main = false
    toLoadHub.visible_settings = false
end

function viewToLoadHubWindow()

    if not float_wnd_is_vr(toloadhub_window) then
        local wLeft, wTop, wRight, wBottom = float_wnd_get_geometry(toloadhub_window)
        toLoadHub.settings.general.window_height = wTop - wBottom
        toLoadHub.settings.general.window_width = wRight - wLeft
    else
        local vrwinWidth, vrwinHeight = float_wnd_get_geometry(toloadhub_window)
        toLoadHub.settings.general.window_height = vrwinHeight
        toLoadHub.settings.general.window_width = vrwinWidth
    end

    if not toLoadHub.first_init then -- Not auto init, and plane not set to zero: RETURN
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
        imgui.TextUnformatted("ToLoadHUB not auto initiated, please initiate.")
        imgui.PopStyleColor()
        if imgui.Button("Init", 100, 30) then
            resetAirplaneParameters()
        end
        return
    end

    -- Starting Onboarding and Passenger/Cargo Selection
    if not toLoadHub.phases.is_onboarded and not toLoadHub.phases.is_onboarding then
        local passengeraNumberChanged, newPassengerNumber = imgui.SliderInt("Passengers number", toLoadHub.pax_count, 0, toLoadHub.max_passenger, "Value: %d")
        if passengeraNumberChanged then
            toLoadHub.pax_count = newPassengerNumber
        end

        local cargoNumberChanged, newCargoNumber = imgui.SliderInt("Cargo KG", toLoadHub.cargo, 0, toLoadHub.max_cargo_aft + toLoadHub.max_cargo_aft, "Value: %d")
        if cargoNumberChanged then
            toLoadHub.cargo = newCargoNumber
        end

        if imgui.Button("Get from Simbrief") then
            fetchSimbriefFPlan()
        end
        imgui.SameLine(155)
        if imgui.Button("Set random passenger number") then
            setRandomNumberOfPassengers()
        end

        if (toLoadHub.pax_count > 0 or toLoadHub.cargo > 0) then
            if (toLoadHub_Doors_1 and toLoadHub_Doors_1>0) or (toLoadHub_Doors_2 and toLoadHub_Doors_2 > 1) or
               (toLoadHub_Doors_6 and toLoadHub_Doors_6 >1 and (PLANE_ICAO == "A321" or PLANE_ICAO == "A21N" or PLANE_ICAO == "A346" or PLANE_ICAO == "A339")) then
                imgui.Separator()
                imgui.Spacing()

                if imgui.Button("Start Boarding") then
                    toLoadHub_PaxDistrib = math.random(toLoadHub.pax_distribution_range[1], toLoadHub.pax_distribution_range[2]) / 100
                    toLoadHub.next_boarding_check = os.time()
                    toLoadHub.next_cargo_check = os.time()
                    toLoadHub.phases.is_onboarding = true
                end
            elseif toLoadHub.settings.door.open_boarding > 0 then
                if imgui.Button("Start Boarding (Auto Open Doors)") then
                    openDoors(true)
                    toLoadHub_PaxDistrib = math.random(toLoadHub.pax_distribution_range[1], toLoadHub.pax_distribution_range[2]) / 100
                    toLoadHub.next_boarding_check = os.time()
                    toLoadHub.next_cargo_check = os.time()
                    toLoadHub.phases.is_onboarding = true
                end
            else
                imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
                imgui.TextUnformatted("Open the doors to start the boarding.")
                imgui.PopStyleColor()
            end
        elseif toLoadHub.pax_count <= 0 or toLoadHub.cargo <= 0 then
            imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
            imgui.TextUnformatted("Please add at least one passenger or some cargo.")
            imgui.PopStyleColor()
        end
    end

    -- Onboarding Phase
    if toLoadHub.phases.is_onboarding and not toLoadHub.phases.is_onboarding_pause and not toLoadHub.phases.is_onboarded then
        if toLoadHub.pax_count > 0 and not toLoadHub.phases.is_pax_onboarded then
            imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
            imgui.TextUnformatted(string.format("Boarding in progress %s / %s boarded", math.floor(toLoadHub_NoPax), toLoadHub.pax_count))
            imgui.PopStyleColor()
        elseif toLoadHub.pax_count > 0 and toLoadHub.phases.is_pax_onboarded then
            imgui.PushStyleColor(imgui.constant.Col.Text, 0xFFFFD700)
            imgui.TextUnformatted(string.format("Passenger boarded %s", toLoadHub_NoPax))
            imgui.PopStyleColor()
        else
            imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF88C0D0)
            imgui.TextUnformatted(string.format("No passenger to board"))
            imgui.PopStyleColor()
        end
        if toLoadHub.cargo > 0 and not toLoadHub.phases.is_cargo_onboarded then
            if toLoadHub.phases.is_cargo_started then
                imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
                imgui.TextUnformatted(string.format("Cargo in progress:"))
                imgui.Spacing()
                imgui.SameLine(50)
                imgui.TextUnformatted(string.format("FWD %.2f T / %.2f T loaded", toLoadHub_FwdCargo / 1000, toLoadHub.cargo_fwd / 1000))
                imgui.Spacing()
                imgui.SameLine(50)
                imgui.TextUnformatted(string.format("AFT %.2f T / %.2f T loaded", toLoadHub_AftCargo / 1000, toLoadHub.cargo_aft / 1000))
                imgui.PopStyleColor()
            else
                imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF88C0D0)
                imgui.TextUnformatted(string.format("Cargo loading has not started yet."))
                imgui.PopStyleColor()
            end
        elseif toLoadHub.cargo > 0 and toLoadHub.phases.is_cargo_onboarded then
            imgui.PushStyleColor(imgui.constant.Col.Text, 0xFFFFD700)
            imgui.TextUnformatted(string.format("Cargo loaded %.2f T", (toLoadHub_AftCargo + toLoadHub_FwdCargo) / 1000 ))
            imgui.PopStyleColor()
        else
            imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF88C0D0)
            imgui.TextUnformatted(string.format("No extra cargo to load"))
            imgui.PopStyleColor()
        end

        if imgui.Button("Pause Boarding") then
            toLoadHub.phases.is_onboarding_pause = true
        end
    end

    -- Onboarding Phase Pause
    if toLoadHub.phases.is_onboarding and toLoadHub.phases.is_onboarding_pause and not toLoadHub.phases.is_onboarded then
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFFFFD700)
        if toLoadHub.pax_count > 0 and not toLoadHub.phases.is_pax_onboarded then
            imgui.TextUnformatted(string.format("Remaining passengers to board: %s / %s", toLoadHub.pax_count-math.floor(toLoadHub_NoPax), toLoadHub.pax_count))
        end
        if toLoadHub.cargo > 0 and not toLoadHub.phases.is_cargo_onboarded then
            imgui.TextUnformatted(string.format("Remaining cargo to load: %.2f T / %.2f T", (toLoadHub.cargo - (toLoadHub_FwdCargo + toLoadHub_AftCargo)) / 1000, toLoadHub.cargo / 1000))
        end
        imgui.PopStyleColor()
        if imgui.Button("Resume Boarding") then
            toLoadHub.phases.is_onboarding_pause = false
        end
        imgui.SameLine(150)
        if imgui.Button("Reset") then
            resetAirplaneParameters()
        end
    end

    -- Omboarded Phase (Boarding Complete), Ready for deboarding
    if toLoadHub.phases.is_onboarded and not toLoadHub.phases.is_deboarding then
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF6AE079)
        imgui.TextUnformatted("Boarding and cargo loading have been completed.")
        imgui.PopStyleColor()
        imgui.Spacing()
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFFFFD700)
        if toLoadHub.pax_count > 0 then
            imgui.TextUnformatted(string.format("Passenger boarded %s", toLoadHub_NoPax))
        end
        if toLoadHub.cargo > 0 then
            imgui.TextUnformatted(string.format("Cargo loaded %.2f T", (toLoadHub_AftCargo + toLoadHub_FwdCargo) / 1000 ))
        end
        imgui.PopStyleColor()

        if (toLoadHub_Doors_1 and toLoadHub_Doors_1 > 0) or (toLoadHub_Doors_2 and toLoadHub_Doors_2 > 1) or
           (toLoadHub_Doors_6 and toLoadHub_Doors_6 >1 and (PLANE_ICAO == "A321" or PLANE_ICAO == "A21N" or PLANE_ICAO == "A346" or PLANE_ICAO == "A339")) then
            if imgui.Button("Start Deboarding") then
                toLoadHub.phases.is_deboarding = true
                toLoadHub.next_boarding_check = os.time()
                toLoadHub.next_cargo_check = os.time()
            end
            imgui.SameLine(200)
        elseif toLoadHub.settings.door.open_deboarding > 0 then
            if imgui.Button("Start Deboarding (Auto Open Doors)") then
                openDoors(false)
                toLoadHub.phases.is_deboarding = true
                toLoadHub.next_boarding_check = os.time()
                toLoadHub.next_cargo_check = os.time()
            end
        else
            imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
            imgui.TextUnformatted("Open the doors to start the deboarding.")
            imgui.PopStyleColor()
        end
        if imgui.Button("Reset") then
            resetAirplaneParameters()
        end
    end

     -- Deboarding Phase
    if toLoadHub.phases.is_deboarding and not toLoadHub.phases.is_deboarding_pause and not toLoadHub.phases.is_deboarded then
        if toLoadHub_NoPax > 0 and not toLoadHub.phases.is_pax_deboarded then
            imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
            imgui.TextUnformatted(string.format("Deboarding in progress %s / %s deboarded", math.floor(toLoadHub.pax_count - toLoadHub_NoPax), toLoadHub.pax_count))
            imgui.PopStyleColor()
        elseif toLoadHub_NoPax == 0 and toLoadHub.phases.is_pax_deboarded then
            imgui.PushStyleColor(imgui.constant.Col.Text, 0xFFFFD700)
            imgui.TextUnformatted("Passenger deboarded")
            imgui.PopStyleColor()
        else
            imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF88C0D0)
            imgui.TextUnformatted(string.format("No passenger to deboard"))
            imgui.PopStyleColor()
        end

        if toLoadHub_FwdCargo + toLoadHub_AftCargo > 0 and not toLoadHub.phases.is_cargo_deboarded then
            imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
            imgui.TextUnformatted(string.format("Cargo offloading in progress:"))
            imgui.Spacing()
            imgui.SameLine(50)
            imgui.TextUnformatted(string.format("FWD %.2f T / %.2f T offloaded", (toLoadHub.cargo_fwd - toLoadHub_FwdCargo) / 1000, toLoadHub.cargo_fwd / 1000))
            imgui.Spacing()
            imgui.SameLine(50)
            imgui.TextUnformatted(string.format("AFT %.2f T / %.2f T offloaded", (toLoadHub.cargo_aft - toLoadHub_AftCargo) / 1000, toLoadHub.cargo_aft / 1000))
            imgui.PopStyleColor()
        elseif toLoadHub_FwdCargo + toLoadHub_AftCargo == 0 and toLoadHub.phases.is_cargo_deboarded then
            imgui.PushStyleColor(imgui.constant.Col.Text, 0xFFFFD700)
            imgui.TextUnformatted("Cargo offloaded")
            imgui.PopStyleColor()
        else
            imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF88C0D0)
            imgui.TextUnformatted(string.format("No cargo to offload"))
            imgui.PopStyleColor()
        end
        if imgui.Button("Pause Deboarding") then
            toLoadHub.phases.is_deboarding_pause = true
        end
    end

     -- Deboarding Phase Pause
    if toLoadHub.phases.is_deboarding and toLoadHub.phases.is_deboarding_pause and not toLoadHub.phases.is_deboarded then
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFFFFD700)
        if toLoadHub_NoPax > 0 then
            imgui.TextUnformatted(string.format("Remaining passengers to deboard: %s / %s", toLoadHub_NoPax, toLoadHub.pax_count))
        end
        if toLoadHub_FwdCargo + toLoadHub_AftCargo > 0 then
            imgui.TextUnformatted(string.format("Remaining cargo to offload: %.2f T / %.2f T", (toLoadHub_FwdCargo + toLoadHub_AftCargo) / 1000, toLoadHub.cargo / 1000))
        end
        imgui.PopStyleColor()
        if imgui.Button("Resume Deboarding") then
            toLoadHub.phases.is_deboarding_pause = false
        end
        imgui.SameLine(150)
        if imgui.Button("Reset") then
            resetAirplaneParameters()
        end
    end

    -- Deboarded Phase (Deboard Complete), Ready for a new flight!
    if toLoadHub.phases.is_deboarded then
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF87CEFA)
        imgui.TextUnformatted("Deboarding and cargo offloaded have been completed!")
        imgui.PopStyleColor()
        imgui.Spacing()
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFFFFD700)
        imgui.PopStyleColor()

        if imgui.Button("Flight completed! Reset") then
            resetAirplaneParameters()
        end
    end

    -- Time Selector for passengers
    if (toLoadHub.pax_count > 0 or toLoadHub.cargo > 0) and
       ((not toLoadHub.phases.is_onboarded and (not toLoadHub.phases.is_onboarding or toLoadHub.phases.is_onboarding_pause)) or
       (toLoadHub.phases.is_onboarded and not toLoadHub.phases.is_deboarded and (not toLoadHub.phases.is_deboarding or toLoadHub.phases.is_deboarding_pause))) then
        local generalSpeed = 3

        if (toLoadHub_Doors_1 and toLoadHub_Doors_1 > 0) and ((toLoadHub_Doors_2 and toLoadHub_Doors_2 > 1) or
           (toLoadHub_Doors_6 and toLoadHub_Doors_6 > 1 and (PLANE_ICAO == "A321" or PLANE_ICAO == "A21N" or PLANE_ICAO == "A346" or PLANE_ICAO == "A339"))) then
            imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF6AE079)
            imgui.TextUnformatted("Both doors are open and in use.")
            imgui.PopStyleColor()
            generalSpeed = 2
        end

        if generalSpeed == 3 and 
           ((toLoadHub_Doors_1 and toLoadHub_Doors_1 == 0 and toLoadHub_Doors_2 and toLoadHub_Doors_2 == 0 and 
            (toLoadHub.settings.door.open_boarding > 1 and not toLoadHub.phases.is_onboarded) or 
            (toLoadHub.settings.door.open_deboarding > 1 and toLoadHub.phases.is_onboarded)
           ) or 
           (toLoadHub_Doors_6 and toLoadHub_Doors_6 == 0 and (PLANE_ICAO == "A321" or PLANE_ICAO == "A21N" or PLANE_ICAO == "A346" or PLANE_ICAO == "A339") and
            (toLoadHub.settings.door.open_boarding > 1 and not toLoadHub.phases.is_onboarded) or 
            (toLoadHub.settings.door.open_deboarding > 1 and toLoadHub.phases.is_onboarded)
           )) then
            imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF6AE079)
            imgui.TextUnformatted("All passenger doors will be operated.")
            imgui.PopStyleColor()
            generalSpeed = 2
        end

        if (toLoadHub.settings.door.open_boarding and not toLoadHub.phases.is_onboarded) or
           (toLoadHub.settings.door.open_deboarding and toLoadHub.phases.is_onboarded) or
           (toLoadHub_Doors_1 and toLoadHub_Doors_1 > 0) or (toLoadHub_Doors_2 and toLoadHub_Doors_2 > 1) or
           (toLoadHub_Doors_6 and toLoadHub_Doors_6 > 1 and (PLANE_ICAO == "A321" or PLANE_ICAO == "A21N" or PLANE_ICAO == "A346" or PLANE_ICAO == "A339")) then
            local fastModeMinutes = math.floor(toLoadHub.pax_count * generalSpeed / 60 + 0.5)
            local realModeMinutes = math.floor(toLoadHub.pax_count * (generalSpeed * 2) / 60 + 0.5)
            if toLoadHub.settings.general.simulate_cargo then
                local fastModeCargoMinutes = math.floor(((toLoadHub.cargo * toLoadHub.cargo_speeds[2] * 0.7) / toLoadHub.kgPerUnit) / 60 + 0.3)
                local realModeCargoMinutes = math.floor(((toLoadHub.cargo * toLoadHub.cargo_speeds[3] * 0.7) / toLoadHub.kgPerUnit) / 60 + 0.3)
                fastModeMinutes = calculateTimeWithCargo(fastModeMinutes, fastModeCargoMinutes)
                realModeMinutes = calculateTimeWithCargo(realModeMinutes, realModeCargoMinutes)
            end
            local labelFast = fastModeMinutes < 1
                and "Fast (less than a minute)"
                or string.format("Fast (%d minute%s)", fastModeMinutes, fastModeMinutes > 1 and "s" or "")
            local labelReal = realModeMinutes < 1
                and "Real (less than a minute)"
                or string.format("Real (%d minute%s)", realModeMinutes, realModeMinutes > 1 and "s" or "")

            if imgui.RadioButton("Instant", toLoadHub.settings.general.boarding_speed == 0) then
                toLoadHub.settings.general.boarding_speed = 0
                toLoadHub.boarding_secnds_per_pax = 0
                toLoadHub.boarding_secnds_per_cargo_unit = toLoadHub.cargo_speeds[1]
            end

            if imgui.RadioButton(labelFast, toLoadHub.settings.general.boarding_speed == 1) then
                toLoadHub.settings.general.boarding_speed = 1
                toLoadHub.boarding_secnds_per_pax = generalSpeed
                toLoadHub.boarding_secnds_per_cargo_unit = toLoadHub.cargo_speeds[2]
            end

            if imgui.RadioButton(labelReal, toLoadHub.settings.general.boarding_speed == 2) then
                toLoadHub.settings.general.boarding_speed = 2
                toLoadHub.boarding_secnds_per_pax = generalSpeed * 2
                toLoadHub.boarding_secnds_per_cargo_unit = toLoadHub.cargo_speeds[3]
            end
        end
    end

    -- Settings Menu Button
    if not toLoadHub.visible_settings and not toLoadHub.phases.is_onboarding then
        imgui.Separator()
        imgui.Spacing()
        imgui.SameLine((toLoadHub.settings.general.window_width)-125)
        if imgui.Button("Settings", 100, 30) then
            toLoadHub.visible_settings = true
            toLoadHub.visible_main = false
            openToLoadHubSettingsWindow()
        end
    end
end

function viewToLoadHubWindowSettings()
    if not float_wnd_is_vr(toloadhub_window) then
        local wLeft, wTop, wRight, wBottom = float_wnd_get_geometry(toloadhub_window)
        toLoadHub.settings.general.window_height = wTop - wBottom
        toLoadHub.settings.general.window_width = wRight - wLeft
    else
        local vrwinWidth, vrwinHeight = float_wnd_get_geometry(toloadhub_window)
        toLoadHub.settings.general.window_height = vrwinHeight
        toLoadHub.settings.general.window_width = vrwinWidth
    end

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
    imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
    imgui.TextUnformatted("General Settings:")
    imgui.PopStyleColor()

    local changed, newval
    changed, newval = imgui.Checkbox("Auto Open ToLoad Hub Window", toLoadHub.settings.general.auto_open)
    if changed then toLoadHub.settings.general.auto_open , setSave = newval, true end

    changed, newval = imgui.Checkbox("Automatically initialize airplane", toLoadHub.settings.general.auto_init)
    if changed then toLoadHub.settings.general.auto_init , setSave = newval, true end

    changed, newval = imgui.Checkbox("Simulate Cargo", toLoadHub.settings.general.simulate_cargo)
    if changed then toLoadHub.settings.general.simulate_cargo , setSave = newval, true end

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

    imgui.Separator()
    imgui.Spacing()

    -- Hoppie Settings
    imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
    imgui.TextUnformatted("Hoppie Settings:")
    imgui.PopStyleColor()

    changed, newval = imgui.Checkbox("Enable Loadsheet", toLoadHub.settings.hoppie.enable_loadsheet)
    if changed then toLoadHub.settings.hoppie.enable_loadsheet , setSave = newval, true end

    changed, newval = imgui.Checkbox("Preliminary Loadsheet Only for Long-haul (+7hrs)", toLoadHub.settings.hoppie.preliminary_loadsheet)
    if changed then toLoadHub.settings.hoppie.preliminary_loadsheet , setSave = newval, true end

    imgui.Separator()
    imgui.Spacing()

    -- Door Settings
    imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF95FFF8)
    imgui.TextUnformatted("Door Settings:")
    imgui.PopStyleColor()

    changed, newval = imgui.Checkbox("Close Doors after Boarding", toLoadHub.settings.door.close_boarding)
    if changed then toLoadHub.settings.door.close_boarding , setSave = newval, true end

    changed, newval = imgui.Checkbox("Close Doors after Deboarding", toLoadHub.settings.door.close_deboarding)
    if changed then toLoadHub.settings.door.close_deboarding , setSave = newval, true end

    imgui.TextUnformatted("Auto Open Doors before Boarding:")
    if imgui.RadioButton("No##boarding", toLoadHub.settings.door.open_boarding == 0) then
        toLoadHub.settings.door.open_boarding = 0
        setSave = true
    end
    imgui.SameLine(55)
    if imgui.RadioButton("Yes, Front Door Only##boarding", toLoadHub.settings.door.open_boarding == 1) then
        toLoadHub.settings.door.open_boarding = 1
        setSave = true
    end
    imgui.SameLine(230)
    if imgui.RadioButton("Yes, All Doors##boarding", toLoadHub.settings.door.open_boarding == 2) then
        toLoadHub.settings.door.open_boarding = 2
        setSave = true
    end
    imgui.Spacing()

    imgui.TextUnformatted("Auto Open Doors before Deboarding:")
    if imgui.RadioButton("No##deboarding", toLoadHub.settings.door.open_deboarding == 0) then
        toLoadHub.settings.door.open_deboarding = 0
        setSave = true
    end
    imgui.SameLine(55)
    if imgui.RadioButton("Yes, Front Door Only##deboarding", toLoadHub.settings.door.open_deboarding == 1) then
        toLoadHub.settings.door.open_deboarding = 1
        setSave = true
    end
    imgui.SameLine(230)
    if imgui.RadioButton("Yes, All Doors##deboarding", toLoadHub.settings.door.open_deboarding == 2) then
        toLoadHub.settings.door.open_deboarding = 2
        setSave = true
    end

    if setSave then
        saveSettingsToFileToLoadHub(false)
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

function resetPositionToloadHubWindow()
    toLoadHub.settings.general.window_x = 160
    toLoadHub.settings.general.window_y = 200
    toLoadHub.settings.general.window_width = 400
    toLoadHub.settings.general.window_height = 250
    if toLoadHub.visible_main or toLoadHub.visible_settings then 
        float_wnd_set_position(toloadhub_window, toLoadHub.settings.general.window_x, toLoadHub.settings.general.window_y)
    else
        loadToloadHubWindow()
    end
    
end

-- == Main Loop Often (1 Sec) ==
function toloadHubMainLoop()
    -- All sounds played and airplane debooarded
    if not toLoadHub.what_to_speak and toLoadHub.full_deboard_sound and toLoadHub.boarding_sound_played and toLoadHub.boarding_cargo_sound_played and
       toLoadHub.deboarding_sound_played and toLoadHub.deboarding_cargo_sound_played and toLoadHub.phases.is_deboarded then
        return
    end

    local now = os.time()
    local applyChange = false

    -- Speak Onboarding/Deboarding Status after the Cabin
    if toLoadHub.what_to_speak and now > toLoadHub.wait_until_speak then
        XPLMSpeakString(toLoadHub.what_to_speak)
        toLoadHub.what_to_speak = nil
    end

    -- Onboarding Phase and Finishing Onboarding
    if toLoadHub.phases.is_onboarding and not toLoadHub.phases.is_onboarding_pause and not toLoadHub.phases.is_onboarded then
        if toLoadHub_NoPax < toLoadHub.pax_count and now > toLoadHub.next_boarding_check then
            if toLoadHub.settings.general.boarding_speed == 0 then
                toLoadHub_NoPax = toLoadHub.pax_count
            else
                toLoadHub_NoPax = toLoadHub_NoPax + 1
                applyChange = true
                toLoadHub.next_boarding_check = now + toLoadHub.boarding_secnds_per_pax + math.random(-2, 2)
            end
        end
        if toLoadHub_NoPax >= toLoadHub.pax_count then
            focusOnToLoadHub()
            closeDoors(true)
        end
    end

    -- Loading and Starting Cargo
    if not toLoadHub.phases.is_cargo_started and toLoadHub.phases.is_onboarding and not toLoadHub.phases.is_onboarding_pause and isNoPaxInRangeForCargo() then
        divideCargoFwdAft()
        openDoorsCargo()
        toLoadHub.phases.is_cargo_started = true
    end
    if toLoadHub.phases.is_cargo_started and not toLoadHub.phases.is_onboarding_pause and not toLoadHub.phases.is_onboarded then
        if (toLoadHub_FwdCargo + toLoadHub_AftCargo) < toLoadHub.cargo and now > toLoadHub.next_cargo_check then
            if toLoadHub.settings.general.boarding_speed == 0 or not toLoadHub.settings.general.simulate_cargo then
                toLoadHub_FwdCargo = toLoadHub.cargo_fwd
                toLoadHub_AftCargo = toLoadHub.cargo_aft
            else
                if addingCargoFwdAft() then applyChange = true end
                toLoadHub.next_cargo_check = now + toLoadHub.boarding_secnds_per_cargo_unit + math.random(-2, 2)
            end
        end

         if (toLoadHub_FwdCargo + toLoadHub_AftCargo) >= toLoadHub.cargo then
            focusOnToLoadHub()
            closeDoorsCargo()
         end
    end

    -- Deboarding Phase and Finishing Deboarding
    if toLoadHub.phases.is_deboarding and not toLoadHub.phases.is_deboarding_pause and not toLoadHub.phases.is_deboarded then
        if toLoadHub_NoPax > 0 and now > toLoadHub.next_boarding_check then
             if toLoadHub.settings.general.boarding_speed == 0 then
                toLoadHub_NoPax = 0
            else
                toLoadHub_NoPax = toLoadHub_NoPax - 1
                applyChange = true
                toLoadHub.next_boarding_check = now + toLoadHub.boarding_secnds_per_pax + math.random(-2, 2)
            end
        end
        if toLoadHub_NoPax <= 0 then
            focusOnToLoadHub()
            closeDoors(false)
        end
    end

    -- Unloading and Starting Cargo Deboarding Phase
    if toLoadHub.phases.is_deboarding and not toLoadHub.phases.is_deboarding_pause and not toLoadHub.phases.is_deboarded then
        openDoorsCargo()
        if (toLoadHub_FwdCargo + toLoadHub_AftCargo) > 0 and now > toLoadHub.next_cargo_check then
            if toLoadHub.settings.general.boarding_speed == 0 or not toLoadHub.settings.general.simulate_cargo then
                toLoadHub_FwdCargo = 0
                toLoadHub_AftCargo = 0
            else
                if removingCargoFwdAft() then applyChange = true end
                toLoadHub.next_cargo_check = now + toLoadHub.boarding_secnds_per_cargo_unit + math.random(-2, 2)
            end
        end

         if (toLoadHub_FwdCargo + toLoadHub_AftCargo) <= 0 then
            focusOnToLoadHub()
         end
    end

    -- Play sound if not played yet and they should be
    if toLoadHub_NoPax >= toLoadHub.pax_count and not toLoadHub.boarding_sound_played and toLoadHub.phases.is_pax_onboarded then playChimeSound() end
    if (toLoadHub_FwdCargo + toLoadHub_AftCargo) >= toLoadHub.cargo and not toLoadHub.boarding_cargo_sound_played and toLoadHub.phases.is_cargo_onboarded then playCargoSound() end
    if toLoadHub_NoPax <= 0 and not toLoadHub.deboarding_sound_played and toLoadHub.phases.is_pax_deboarded then playChimeSound() end
    if (toLoadHub_FwdCargo + toLoadHub_AftCargo) <= 0 and not toLoadHub.deboarding_cargo_sound_played and toLoadHub.phases.is_cargo_deboarded then playCargoSound() end
    if toLoadHub_NoPax <= 0 and not toLoadHub.full_deboard_sound and (toLoadHub_FwdCargo + toLoadHub_AftCargo) <= 0 and toLoadHub.phases.is_deboarded then playFinalSound() end

    -- Compliting the Onboarding process (Cargo + Passengers)
    if not toLoadHub.phases.is_pax_onboarded and toLoadHub_NoPax >= toLoadHub.pax_count and toLoadHub.phases.is_onboarding then
        toLoadHub.phases.is_pax_onboarded = true
        applyChange = true
    end
    if not toLoadHub.phases.is_cargo_onboarded and (toLoadHub_FwdCargo + toLoadHub_AftCargo) >= toLoadHub.cargo and toLoadHub.phases.is_onboarding then
        toLoadHub.phases.is_cargo_onboarded = true
        applyChange = true
    end
    if not toLoadHub.phases.is_onboarded and toLoadHub.phases.is_pax_onboarded and toLoadHub.phases.is_cargo_onboarded and toLoadHub.phases.is_onboarding then
        toLoadHub.phases.is_onboarded = true
        applyChange = true
        toLoadHub.hoppie.loadsheet_check = os.time() + 5
    end

    -- Compliting the Deboarding process (Cargo + Passengers)
    if not toLoadHub.phases.is_pax_deboarded and toLoadHub_NoPax <= 0 and toLoadHub.phases.is_deboarding then
        toLoadHub.phases.is_pax_deboarded = true
        applyChange = true
    end
    if not toLoadHub.phases.is_cargo_deboarded and (toLoadHub_FwdCargo + toLoadHub_AftCargo) <= 0 and toLoadHub.phases.is_deboarding then
        toLoadHub.phases.is_cargo_deboarded = true
        applyChange = true
    end
    if not toLoadHub.phases.is_deboarded and toLoadHub_NoPax <= 0 and (toLoadHub_FwdCargo + toLoadHub_AftCargo) <= 0 and toLoadHub.phases.is_deboarding then
        toLoadHub.phases.is_deboarded = true
        applyChange = true
    end

    -- Applying change if needed
    if applyChange then
        toLoadHub_NoPax_XP = toLoadHub_NoPax
        toLoadHub_PaxDistrib_XP = toLoadHub_PaxDistrib
        toLoadHub_FwdCargo_XP = toLoadHub_FwdCargo
        toLoadHub_AftCargo_XP = toLoadHub_AftCargo
        toLoadHub.setWeightCommand = true
        toLoadHub.setWeightTime = os.time() + 2
    end

    if not toLoadHub.hoppie.loadsheet_sent and toLoadHub.settings.hoppie.enable_loadsheet and toLoadHub.phases.is_onboarded then
        local data_f = loadsheetStructure:new()
        data_f.isFinal = true
        data_f.labelText = "@Final@"
        data_f.flt_no = toLoadHub_flight_no
        data_f.zfw = string.format("%.1f",toLoadHub_zfw/1000)
        data_f.zfwcg = string.format("%.1f",toLoadHub_zfwCG)
        data_f.gwcg = string.format("%.1f",toLoadHub_currentCG)
        data_f.f_blk = string.format("%.1f",toLoadHub_WriteFOB_XP/1000)
        if toLoadHub_WriteFOB_XP + 20 < toLoadHub.simbrief.plan_ramp then
            data_f.warning = string.format("%.1f",toLoadHub.simbrief.plan_ramp/1000)
        end
        sendLoadsheetToToliss(data_f)
    end

    if (not toLoadHub.settings.hoppie.preliminary_loadsheet or toLoadHub.simbrief.est_block ~=nil and toLoadHub.simbrief.est_block/60 > 420) and not toLoadHub.hoppie.loadsheet_preliminary_sent and toLoadHub.settings.hoppie.enable_loadsheet and toLoadHub.simbrief.callsign ~= nil and toLoadHub.simbrief.callsign == toLoadHub_flight_no then
        if not toLoadHub.hoppie.loadsheet_preliminary_ready then
            toLoadHub.hoppie.loadsheet_check = os.time() + 3
            toLoadHub.hoppie.loadsheet_preliminary_ready = true
        end
        local data_p = loadsheetStructure:new()
        divideCargoFwdAft()
        setIscsTemporarySimbrief()
        data_p.isFinal = false
        data_p.labelText = "Prelim."
        data_p.zfw = string.format("%.1f", toLoadHub.simbrief.est_zfw/1000)
        data_p.zfwcg = string.format("%.1f", toLoadHub_blockZfwCG)
        data_p.gwcg = string.format("%.1f", toLoadHub_blockCG)
        data_p.f_blk = string.format("%.1f",toLoadHub.simbrief.plan_ramp/1000)
        data_p.flt_no = toLoadHub_flight_no
        sendLoadsheetToToliss(data_p)
    end
    registerSetWeight()
end

-- == Main code ==
debug(string.format("[%s] Version %s initialized.", toLoadHub.title, toLoadHub.version))
dataref("toLoadHub_NoPax_XP", "AirbusFBW/NoPax", "writeable")
dataref("toLoadHub_PaxDistrib_XP", "AirbusFBW/PaxDistrib", "writeable")
dataref("toLoadHub_AftCargo_XP", "AirbusFBW/AftCargo", "writeable")
dataref("toLoadHub_FwdCargo_XP", "AirbusFBW/FwdCargo", "writeable")

dataref("toLoadHub_Doors_1", "AirbusFBW/PaxDoorModeArray", "writeable", 0)
dataref("toLoadHub_Doors_2", "AirbusFBW/PaxDoorModeArray", "writeable", 2)
dataref("toLoadHub_Doors_6", "AirbusFBW/PaxDoorModeArray", "writeable", 6)
dataref("toLoadHub_CargoDoors_1", "AirbusFBW/CargoDoorModeArray", "writeable", 0)
dataref("toLoadHub_CargoDoors_2", "AirbusFBW/CargoDoorModeArray", "writeable", 1)

dataref("toLoadHub_zfw", "toliss_airbus/iscsinterface/zfw", "readonly")
dataref("toLoadHub_zfwCG", "toliss_airbus/iscsinterface/zfwCG", "readonly")
dataref("toLoadHub_currentCG", "toliss_airbus/iscsinterface/currentCG", "readonly")
dataref("toLoadHub_flight_no", "toliss_airbus/init/flight_no", "readonly")
dataref("toLoadHub_simBriefID", "toliss_airbus/iscsinterface/simBriefID", "readonly")
dataref("toLoadHub_hoppieLogon", "toliss_airbus/iscsinterface/hoppieLogon", "readonly")
dataref("toLoadHub_WriteFOB_XP", "AirbusFBW/WriteFOB", "readonly")

-- temporary iscs
dataref("toLoadHub_blockZfwCG", "toliss_airbus/iscsinterface/blockZfwCG", "readonly")
dataref("toLoadHub_blockCG", "toliss_airbus/iscsinterface/blockCG", "readonly")


setAirplaneNumbers()
readSettingsToFile()

if toLoadHub.settings.general.auto_init then
    resetAirplaneParameters()
end
if toLoadHub.settings.simbrief.auto_fetch then
    fetchSimbriefFPlan()
end
add_macro("ToLoad Hub - Main Window", "loadToloadHubWindow()")
add_macro("ToLoad Hub - Reset Window Position", "resetPositionToloadHubWindow()")

create_command("FlyWithLua/TOLOADHUB/Toggle_toloadhub", "Toggle ToLoadHUB window", "toggleToloadHubWindow()", "", "")
create_command("FlyWithLua/TOLOADHUB/ResetPosition_toloadhub", "Reset Position ToLoadHUB window", "resetPositionToloadHubWindow()", "", "")

do_often("toloadHubMainLoop()")

if toLoadHub.settings.general.auto_open then
    loadToloadHubWindow()
end
do_on_exit("saveSettingsToFileToLoadHub(true)")
debug(string.format("[%s] Plugin fully loaded.", toLoadHub.title))
