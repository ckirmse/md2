--!strict

-- thin wrapper around the vendored topbarplus package (out of scope per CLAUDE.md); the
-- library crosses this boundary untyped
local TopBarPlus: any = (require :: any)(script.Parent.Packages.topbarplus)

TopBarPlus.highlightKey = false

return TopBarPlus
