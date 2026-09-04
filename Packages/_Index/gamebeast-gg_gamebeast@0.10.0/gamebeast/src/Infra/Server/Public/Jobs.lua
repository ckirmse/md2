--[[
    The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
    All rights reserved.
    
    Jobs.lua
    
    Description:
        Handles public facing API for binding to custom jobs.
    
--]]

--= Root =--
local Jobs = { }

--= Roblox Services =--

--= Dependencies =--

local RequestFunctionHandler = shared.GBMod("RequestFunctionHandler") ---@module RequestFunctionHandler

--= Types =--

--= Object References =--

--= Constants =--

--= Variables =--

--= Public Variables =--

--= Internal Functions =--

--= API Functions =--

function Jobs:SetCallback(jobName : string, callback : (jobData : {[string] : any}) -> (any))
    return RequestFunctionHandler:SetCallback(jobName, callback)
end

--= Return Module =--
return Jobs