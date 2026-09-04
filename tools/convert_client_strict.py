#!/usr/bin/env python3
"""Mechanical first pass converting a src/client module to --!strict.

Does the repetitive parts of the conversion documented in CLAUDE.md; the result still needs a
hand pass for file-specific casts. Idempotence is not a goal - run once per file.

- inserts --!strict
- function X:name(a, b) -> function X.name(self: X, a: any, b: any)
- collects every `self.<field> =` assignment into an XFields type; field types are inferred
  from new()'s defaults where obvious (booleans, numbers, {} maps, Instance.new results,
  BindableEvent, connections via `:Connect(`), otherwise `any`
- export type X = typeof(setmetatable({} :: XFields, X)) + new() bridge
- `local x -- prevent circular reference` + in-init `x = require(...)` -> Types.X injected
  local + initClass(deps) (appended before the singleton construction)
- RemoteEvents/local template WaitForChild locals -> `: any` with the standard comment
- game.RunService -> runService service local; game.Players.LocalPlayer -> typed
"""
import re
import sys

path = sys.argv[1]
src = open(path).read()
cls = re.search(r'local (\w+) = \{\}\n\1\.__index = \1', src).group(1)

# 1) lazy requires -> injection
lazy_locals = re.findall(r'local (\w+)(?::\s*[\w.]+)? -- prevent circular[^\n]*\n', src)
injected = []
for name in lazy_locals:
    m = re.search(r'\t+' + name + r' = require\("\./' + r'(\w+)' + r'"\)\n', src)
    if m:
        target = m.group(1)
        injected.append((name, target))
        src = src.replace(m.group(0), '')
        src = re.sub(r'local ' + name + r'(?::\s*[\w.]+)? -- prevent circular[^\n]*\n',
                     f'local {name}: Types.{target} -- injected via initClass(deps); typed through Types.luau to avoid the require cycle\n', src)
    else:
        # dead lazy local: drop it
        src = re.sub(r'local ' + name + r'(?::\s*[\w.]+)? -- prevent circular[^\n]*\n', '', src)

# 2) header
src = '--!strict\n\n' + src

# 3) services / player
if 'game.RunService' in src:
    src = src.replace('local ' + cls + ' = {}', 'local runService = game:GetService("RunService")\n\nlocal ' + cls + ' = {}', 1)
    src = src.replace('game.RunService', 'runService')
src = src.replace('local player = game.Players.LocalPlayer', 'local player = game:GetService("Players").LocalPlayer :: Player')
src = src.replace('player.PlayerGui:WaitForChild', 'player:WaitForChild("PlayerGui"):WaitForChild')
src = re.sub(r'local PlayerGui = player:FindFirstChild\("PlayerGui"\)\n', 'local PlayerGui = player:FindFirstChild("PlayerGui") :: Instance\n', src)
# the character rig's children only exist at runtime
src = src.replace('player.Character.HumanoidRootPart', '(player.Character :: any).HumanoidRootPart')
src = src.replace('player.Character.Humanoid', '(player.Character :: any).Humanoid')
src = src.replace('player.Backpack', '(player :: any).Backpack')

# 4) untyped Studio boundary locals
src = re.sub(r'local RemoteEvents = ReplicatedStorage:WaitForChild\("RemoteEvents"\)',
             '-- the RemoteEvents children only exist in Studio, so they are untyped here\nlocal RemoteEvents: any = ReplicatedStorage:WaitForChild("RemoteEvents")', src)
src = re.sub(r'local (\w+) = utils\.findFirstDescendant\(', r'local \1: any = utils.findFirstDescendant(', src)

# 5) collect self fields and infer types from defaults in new() and assignments
fields = {}
for m in re.finditer(r'self\.(\w+) = ([^\n]+)', src):
    name, val = m.group(1), m.group(2).strip()
    prev = fields.get(name)
    t = 'any'
    if val in ('true', 'false'): t = 'boolean'
    elif re.fullmatch(r'-?\d+(\.\d+)?', val): t = 'number'
    elif val == '{}': t = '{ [any]: any }'
    elif val == 'nil': t = 'any'
    elif val.startswith('Instance.new("BindableEvent")'): t = 'BindableEvent'
    elif ':Connect(' in val or val.endswith(':Connect('): t = 'RBXScriptConnection?'
    elif val.startswith('Vector2.'): t = 'Vector2'
    elif val.startswith('Vector3.'): t = 'Vector3'
    elif val.startswith('CFrame.'): t = 'CFrame'
    # widen across multiple assignments: any nil/mixed assignment degrades to any, which
    # keeps method calls and arithmetic permissive for the hand-tightening pass
    if prev and prev != t:
        t = 'any'
    fields[name] = t

fields_lines = '\n'.join(f'\t{n}: {t},' for n, t in sorted(fields.items()))
type_block = f'type {cls}Fields = {{\n{fields_lines}\n}}\n\nexport type {cls} = typeof(setmetatable({{}} :: {cls}Fields, {cls}))\n\n'

# insert before first method definition
first_fn = re.search(r'function ' + cls + r'[:.]', src)
src = src[:first_fn.start()] + type_block + src[first_fn.start():]

# 6) colon -> dot with any params
def conv(m):
    name, params = m.group(1), m.group(2)
    typed = [p.strip() + ': any' for p in params.split(',') if p.strip()]
    inner = ', '.join([f'self: {cls}'] + typed)
    return f'function {cls}.{name}({inner})'
src = re.sub(r'function ' + cls + r':(\w+)\(([^)]*)\)', conv, src)

# 7) new() bridge
src = re.sub(r'function ' + cls + r'\.new\(\)\n\tlocal self = setmetatable\(\{\}, ' + cls + r'\)',
             f'function {cls}.new(): {cls}\n\tlocal self = setmetatable({{}} :: {cls}Fields, {cls})', src)

# 8) initClass
if injected:
    lines = '\n'.join(f'\t{n} = deps.{n}' for n, _ in injected)
    src = src.replace(f'local singleton = {cls}.new()',
                      f'function {cls}.initClass(deps: any)\n{lines}\nend\n\nlocal singleton = {cls}.new()')
    if 'local Types = require("./Types")' not in src:
        # Types must be in scope before the first injected local's annotation
        first_inj = src.find('-- injected via initClass(deps)')
        line_start = src.rfind('\n', 0, first_inj) + 1
        src = src[:line_start] + 'local Types = require("./Types")\n' + src[line_start:]

open(path, 'w').write(src)
print(f'converted {path}: {len(fields)} fields, injected {[n for n,_ in injected]}')
