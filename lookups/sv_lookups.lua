--[[
    Sonaran CAD Plugins

    Plugin Name: lookups
    Creator: SonoranCAD
    Description: Implements the name/plate lookup API
]]

local pluginConfig = Config.GetPluginConfig("lookups")

if pluginConfig.enabled then

    registerApiType("LOOKUP", "general")

    local LookupCache = {}

    local Lookup = {
        first = nil,
        last = nil,
        mi = nil,
        plate = nil,
        types = nil,
        lastFetched = nil
    }
    function Lookup.Create(first, last, mi, plate, types, response)
        local self = shallowcopy(Lookup)
        self.first = first
        self.last = last
        self.mi = mi
        self.plate = plate
        self.types = types
        self.lastFetched = GetGameTimer()
        self.response = response
        return self
    end
    function Lookup:UpdateCache()
        self.response = info
        self.lastFetched = GetGameTimer()
    end
    function Lookup:IsMatch(first, last, mi, plate, types)
        if self.first == first and self.last == last and self.mi == mi and self.plate == plate then
            for _, v in pairs(self.types) do
                local match = false
                for __, v2 in pairs(types) do
                    if v2 == v then
                        match = true
                    end
                end
                if not match then
                    return false
                end
            end
            return true
        else
            return false
        end
    end

    -- Stale lookup garbage collector
    local function PurgeStaleLookups()
        local currentTime = GetGameTimer()
        for k, v in pairs(LookupCache) do
            local garbageTime = v.lastFetched + (pluginConfig.maxCacheTime*1000)
            if currentTime >= garbageTime then
                LookupCache[k] = nil
                debugPrint(("Stale lookup purged %s"):format(k))
            end
        end
        SetTimeout(pluginConfig.stalePurgeTimer*1000, PurgeStaleLookups)
    end

    PurgeStaleLookups()

    function cadLookup(data, callback, autoLookup)
        -- check if the lookupData has all required fields
        data["first"] = data["first"] == nil and "" or data["first"]
        data["mi"] = data["mi"] == nil and "" or data["mi"]
        data["last"] = data["last"] == nil and "" or data["last"]
        data["plate"] = data["plate"] == nil and "" or data["plate"]:match("^%s*(.-)%s*$")
        data["types"] = data["types"] == nil and {2,3,4,5} or data["types"]
        if autoLookup ~= nil then
            data["apiId"] = autoLookup
        end
        -- check cache
        for k, v in pairs(LookupCache) do
            if v:IsMatch(data.first, data.last, data.mi, data.plate, data.types) then
                debugLog("Returning cached response")
                callback(json.decode(v.response))
                return
            end
        end
        performApiRequest({data}, "LOOKUP", function(result)
            debugLog("Performed lookup")
            local lookup = json.decode(result)
            local l = Lookup.Create(data.first, data.last, data.mi, data.plate, data.types, result)
            table.insert(LookupCache, l)
            callback(lookup)
        end)
            
    end

    function cadLookupInt(searchType, value, types, callback, autoLookup)

    end

    --[[
        cadNameLookup
            first: First Name
            last: Last Name
            mi: Middle Initial
            callback: function called with return data
    ]]
    function cadNameLookup(first, last, mi, callback)
        local data = {}
        data.first = first
        data.last = last
        data.mi = mi
        cadLookup(data, callback, autoLookup)
    end

    --[[
        cadPlateLookup
            plate: plate number
            basicFlag: deprecated
            callback: the function called with the return data
            autoLookup: when populated with an API ID, pops open a search window on the officer's CAD (optional)
    ]]
    function cadPlateLookup(plate, basicFlag, callback, autoLookup)
        local data = {}
        data["plate"] = plate
        if autoLookup ~= nil then
            data["apiId"] = autoLookup
        end
        cadLookup(data, callback, autoLookup)
        
    end

    function cadGetInformation(plate, callback, autoLookup)
        local data = {}
        data["plate"] = plate
        if autoLookup ~= nil then
            data["apiId"] = autoLookup
        end
        cadLookup(data, function(result)
            local regData = {}
            local charData = {}
            local vehData = {}
            local boloData = {}
            if result ~= nil and result.records ~= nil then
                for _, record in pairs(result.records) do
                    if record.type == 5 then
                        for _, section in pairs(record.sections) do
                            if section.category == 0 then
                                local reg = {}
                                for _, field in pairs(section.fields) do
                                    reg[field.label] = field.value
                                end
                                table.insert(regData, reg)
                            elseif section.category == 3 then
                                for _, field in pairs(section.fields) do
                                    if field["data"] ~= nil then
                                        if field.data["first"] ~= nil then
                                            table.insert(charData, field.data)
                                        end
                                    end
                                end
                            elseif section.category == 4 then
                                for _, field in pairs(section.fields) do
                                    
                                    if field["data"] ~= nil then
                                        if field.data["plate"] ~= nil then
                                            table.insert(vehData, field.data)
                                        end
                                    end
                                end
                            end
                        end
                    elseif record.type == 3 then
                        for _, section in pairs(record.sections) do
                            if section.category == 1 then-- flags
                                for _, field in pairs(section.fields) do
                                    if field["data"] ~= nil then -- is a BOLO, might not have flags
                                        if field["data"]["flags"] ~= nil then
                                            boloData = field["data"]["flags"]
                                        else
                                            boloData = {"BOLO"}
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            callback(regData, vehData, charData, boloData)
        end, autoLookup)
    end

    exports('cadNameLookup', cadNameLookup)
    exports('cadPlateLookup', cadPlateLookup)

    -- The follow two commands are for developer use to analyze API responses

    RegisterCommand("platefind", function(source, args, rawCommand)
        if args[1] ~= nil then
            cadPlateLookup(args[1], true, function(data)
                print(("Raw data: %s"):format(json.encode(data)))
            end)
        end
    end, true)

    RegisterCommand("namefind", function(source, args, rawCommand)
        if args[1] ~= nil then
            local firstName = args[1]
            local lastName = args[2] ~= nil and args[2] or ""
            local mi = args[3] ~= nil and args[3] or ""
            cadNameLookup(firstName, lastName, mi, function(data)
                print(("Raw data: %s"):format(json.encode(data)))
            end)
        end
    end, true)

end