--[[
    Requires dashboard interaction.
    Set a config equal to:

    Test = {
        A = {
            B = "Hello"
        }
    }

    Then, run the test.
]]

return function()
    local Gamebeast = require(game:GetService("ReplicatedStorage"):WaitForChild("Gamebeast"))
    local ConfigsService = Gamebeast:GetService("Configs") :: Gamebeast.ConfigsService

    describe("Config", function()
        it("should get config ready status", function()
            local configReady = ConfigsService:IsReady()
            expect(configReady).to.be.a("boolean")
        end)

        it("should get a config", function()
            local config = ConfigsService:Get("Test")
            expect(config).to.be.ok()
        end)

        it("should get a config from table", function()
            local config = ConfigsService:Get({"Test", "A", "B"})
            expect(config).to.be.equal("Hello")
        end)

        it("should listen to a config changing", function()
            ConfigsService:OnChanged("Test", function(newValue)
                expect(newValue).to.be.ok()
            end)
        end)

        it("should listen to a config changing from table", function()
            ConfigsService:OnChanged({"Test", "A", "B"}, function(newValue)
                expect(newValue).to.be.ok()
            end)
        end)
    end)
end