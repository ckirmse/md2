--[[
    The Gamebeast SDK is Copyright © 2023 Gamebeast, Inc. to present.
    All rights reserved.
    
    DataCache.lua
    
    Description:
        Simple module for caching data that can be accessed by other modules.
    
--]]

--= Root =--
local DataCache = { }

--= Roblox Services =--
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--= Dependencies =--

--= Types =--

--= Object References =--

--= Constants =--

--= Variables =--

local Cache = {}

--= Public Variables =--

--= Internal Functions =--

--= API Functions =--

function DataCache:Set(key : string, value : any)
    Cache[key] = value
end

function DataCache:Get(key : string) : any
    return Cache[key]
end

--= Return Module =--
return DataCache