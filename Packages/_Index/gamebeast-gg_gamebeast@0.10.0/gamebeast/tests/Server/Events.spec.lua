--[[
    Requires dashboard interaction.
    Set an event equal to:
    Name: TestEvent
    {
        A = {
            B = "Hello"
        }
    }

    Then, run the test.

    Start the event and make sure it ends a few seconds later.
]]

return function()
    local Gamebeast = require(game:GetService("ReplicatedStorage"):WaitForChild("Gamebeast"))
    local EventsService = Gamebeast:GetService("Events") :: Gamebeast.EventsService

    describe("Events", function()
        it("should get event data", function()
            local eventData = EventsService:GetEventData("TestEvent")
            expect(eventData).to.be.ok()
        end)

        it("should listen to an event starting", function()
            EventsService:OnStart("TestEvent", function(eventData)
                expect(eventData).to.be.ok()
            end)
        end)

        it("should listen to an event ending", function()
            EventsService:OnEnd("TestEvent", function(eventData)
                expect(eventData).to.be.ok()
            end)
        end)
    end)
end