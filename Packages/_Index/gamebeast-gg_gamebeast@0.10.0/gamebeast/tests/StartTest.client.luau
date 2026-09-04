local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tester = require(ReplicatedFirst:WaitForChild("Tests").Tester)

local ClientTestRemote = ReplicatedStorage:WaitForChild("TestRunnerRemote")
ClientTestRemote.OnClientEvent:Connect(function()
    Tester:Run({
        --
    })
end)