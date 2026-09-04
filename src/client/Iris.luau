--!strict

-- thin wrapper around the vendored iris package (out of scope per CLAUDE.md); the library's
-- immediate-mode API is genuinely dynamic, so it crosses this boundary untyped
local Iris: any = (require :: any)(script.Parent.Packages.iris).Init()

return Iris
