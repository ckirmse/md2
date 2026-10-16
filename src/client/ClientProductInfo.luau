--!strict

-- Roblox developer product lookups for the client: the live Robux price and whether the product is for sale. Results
-- are cached, and lookups already in flight for the same product are shared, so several callers cost one request.
local ClientProductInfo = {}

local MarketplaceService = game:GetService("MarketplaceService")

export type ProductInfo = {
	robuxPrice: number?,
	isForSale: boolean,
}

local productInfoCache: { [number]: ProductInfo } = {}
local pendingCallbacks: { [number]: { (info: ProductInfo) -> () } } = {}

-- the callback runs once the info is known, immediately when it is cached. A failed lookup answers "not for sale" and
-- is not cached, so a later call tries again
function ClientProductInfo.getProductInfoAsync(productId: number, callback: (info: ProductInfo) -> ())
	local cached = productInfoCache[productId]
	if cached then
		callback(cached)
		return
	end

	local pending = pendingCallbacks[productId]
	if pending then
		table.insert(pending, callback)
		return
	end
	pendingCallbacks[productId] = { callback }

	task.spawn(function()
		local isSuccess, productInfo = pcall(function()
			return MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product) :: any
		end)

		local info: ProductInfo
		if isSuccess and type(productInfo) == "table" then
			info = {
				robuxPrice = (productInfo :: any).PriceInRobux,
				isForSale = (productInfo :: any).IsForSale == true,
			}
			productInfoCache[productId] = info
		else
			warn("ClientProductInfo: GetProductInfoAsync failed for", productId, productInfo)
			info = { robuxPrice = nil, isForSale = false }
		end

		local callbacks = pendingCallbacks[productId]
		pendingCallbacks[productId] = nil
		for _, pendingCallback in callbacks do
			pendingCallback(info)
		end
	end)
end

return ClientProductInfo
