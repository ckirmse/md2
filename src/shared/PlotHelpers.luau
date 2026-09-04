--!strict

local PlotHelpers = {}

local collectionService = game:GetService("CollectionService")

local Attributes = require("./Attributes")
local enums = require("./Enums")

local expansionVanityAreas: { number } = {enums.VanityAreas.EXPANSION_1, enums.VanityAreas.EXPANSION_2, enums.VanityAreas.EXPANSION_3, enums.VanityAreas.EXPANSION_4}

function PlotHelpers.getPlotCFrame(plotIndex: number): CFrame?
	local origins = collectionService:GetTagged("Origin")
	for _, origin in origins do
		if origin:GetAttribute(Attributes.INDEX) ~= plotIndex then
			continue
		end

		-- origins are attachments placed in the level geometry
		return (origin :: Attachment).WorldCFrame
	end

	warn("invalid plot index missing an origin", plotIndex)

	return nil
end

function PlotHelpers.translateCFramePlotToWorld(cframe: CFrame, plotIndex: number): CFrame
	local plotCFrame = assert(PlotHelpers.getPlotCFrame(plotIndex), "no plot cframe for plot index " .. tostring(plotIndex))
	return plotCFrame * cframe
end

function PlotHelpers.translateCFrameWorldToPlot(cframe: CFrame, plotIndex: number): CFrame
	local plotCFrame = assert(PlotHelpers.getPlotCFrame(plotIndex), "no plot cframe for plot index " .. tostring(plotIndex))
	return plotCFrame:Inverse() * cframe
end

function PlotHelpers.getInnerVanityPlacementByVanityArea(vanityArea: number): number?
	if vanityArea == enums.VanityAreas.EXPANSION_1 then
		return enums.VanityPlacements.EXPANSION_1_INNER
	elseif vanityArea == enums.VanityAreas.EXPANSION_2 then
		return enums.VanityPlacements.EXPANSION_2_INNER
	elseif vanityArea == enums.VanityAreas.EXPANSION_3 then
		return enums.VanityPlacements.EXPANSION_3_INNER
	elseif vanityArea == enums.VanityAreas.EXPANSION_4 then
		return enums.VanityPlacements.EXPANSION_4_INNER
	end

	warn("unknown expansion vanity area", vanityArea)

	return nil
end

function PlotHelpers.getOuterVanityPlacementByVanityArea(vanityArea: number): number?
	if vanityArea == enums.VanityAreas.EXPANSION_1 then
		return enums.VanityPlacements.EXPANSION_1_OUTER
	elseif vanityArea == enums.VanityAreas.EXPANSION_2 then
		return enums.VanityPlacements.EXPANSION_2_OUTER
	elseif vanityArea == enums.VanityAreas.EXPANSION_3 then
		return enums.VanityPlacements.EXPANSION_3_OUTER
	elseif vanityArea == enums.VanityAreas.EXPANSION_4 then
		return enums.VanityPlacements.EXPANSION_4_OUTER
	end

	warn("unknown expansion vanity area", vanityArea)

	return nil
end

function PlotHelpers.getExpansionVanityAreas(): { number }
	return expansionVanityAreas
end

return PlotHelpers
