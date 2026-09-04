--!strict

local ModificationDataStore = {}
ModificationDataStore.__index = ModificationDataStore

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameAssets = ReplicatedStorage:WaitForChild("GameAssets")

local enums = require("@game/ReplicatedStorage/Shared/Enums")

export type ModificationData = {
	value: number,
	cropParticleTemplatePath: string,
	harvestedParticleParentTemplatePath: string,
	-- resolved from cropParticleTemplatePath by tryInitData
	cropParticle: Instance?,
}

type ModificationDataStoreFields = {
	modificationDatas: { ModificationData },
}

export type ModificationDataStore = typeof(setmetatable({} :: ModificationDataStoreFields, ModificationDataStore))

local modificationDatas: { ModificationData } = {
	{
		value = enums.Modifications.WET,
		cropParticleTemplatePath = "ParticleEffects.CropModifications.RainPlant.Fruit_Green_Basic.RainCropParticleEmitter",
		harvestedParticleParentTemplatePath = "ParticleEffects.HarvestCropModifications.WaterHarvest",
	},
	{
		value = enums.Modifications.BLOOM,
		cropParticleTemplatePath = "ParticleEffects.CropModifications.BloomPlant.Fruit_Green_Basic.BloomCropParticleEmitter",
		harvestedParticleParentTemplatePath = "ParticleEffects.HarvestCropModifications.BloomHarvest",
	},
	{
		value = enums.Modifications.WINDY,
		cropParticleTemplatePath = "ParticleEffects.CropModifications.WindPlant.Fruit_Green_Basic.WindCropParticleEmitter",
		harvestedParticleParentTemplatePath = "ParticleEffects.HarvestCropModifications.WindHarvest",
	},
	{
		value = enums.Modifications.HOT,
		cropParticleTemplatePath = "ParticleEffects.CropModifications.HeatPlant.Fruit_Green_Basic.HeatCropParticleEmitter",
		harvestedParticleParentTemplatePath = "ParticleEffects.HarvestCropModifications.HeatHarvest",
	},
	{
		value = enums.Modifications.GREEN_FLAME,
		cropParticleTemplatePath = "ParticleEffects.CropModifications.GreenFlame.GreenFlameCropParticleEmitter",
		harvestedParticleParentTemplatePath = "ParticleEffects.HarvestCropModifications.GreenHarvest",
	},
	{
		value = enums.Modifications.BLUE_FLAME,
		cropParticleTemplatePath = "ParticleEffects.CropModifications.BlueFlame.BlueFlameCropParticleEmitter",
		harvestedParticleParentTemplatePath = "ParticleEffects.HarvestCropModifications.BlueHarvest",
	},
	{
		value = enums.Modifications.RED_FLAME,
		cropParticleTemplatePath = "ParticleEffects.CropModifications.RedFlame.RedFlameCropParticleEmitter",
		harvestedParticleParentTemplatePath = "ParticleEffects.HarvestCropModifications.RedHarvest",
	},
}

function ModificationDataStore.getModificationDataByValue(self: ModificationDataStore, value: number): ModificationData?
	for _, modificationData in self.modificationDatas do
		if modificationData.value ~= value then
			continue
		end
		return modificationData
	end
	return nil
end

function ModificationDataStore.tryInitData(self: ModificationDataStore): boolean
	local alreadyDone = 0
	local loadedNow = 0
	local failedNow = 0
	self.modificationDatas = modificationDatas
	for _, modificationData in self.modificationDatas do
		if modificationData.cropParticle then
			alreadyDone += 1
			continue
		end
		local path = string.split(modificationData.cropParticleTemplatePath, ".")
		local inst: Instance? = GameAssets
		for _, pathNode in path do
			inst = (inst :: Instance):WaitForChild(pathNode, 2)
			if inst == nil then
				print("failed to load crop effect template", path, pathNode)
				break
			end
		end
		if not inst then
			failedNow += 1
			continue
		end
		modificationData.cropParticle = inst
		loadedNow += 1
	end

	if alreadyDone > 0 or failedNow > 0 then
		warn("modificationDataStore init, already done", alreadyDone, "loaded now", loadedNow, "failedNow", failedNow)
	end

	return failedNow == 0
end

function ModificationDataStore.new(): ModificationDataStore
	local self: ModificationDataStore = setmetatable({} :: ModificationDataStoreFields, ModificationDataStore)

	while true do
		local success, _ = pcall(
			function ()
				self:tryInitData()
			end
		)
		if success then
			break
		end

		print("failed to init weather data store")
		task.wait(2)
		print("retrying to init weather data store")
	end

	return self
end

local singleton = ModificationDataStore.new()

return singleton
