-- cortex-lib draws one key-help strip per resource, bottom right. Several
-- cortex-admin features can want it at once (vMenu mode's menu keys while
-- noclip flies), so each sets a named layer and the strip shows them together,
-- menu keys first. A layer only reaches cortex-lib when the strip changes.
local Admin = EsAdmin
local ORDER = { 'vmenu', 'noclip' }
local MAX_ITEMS = 16
local layers, shown = {}, nil

local function render()
    local items = {}
    for _, id in ipairs(ORDER) do
        for _, item in ipairs(layers[id] or {}) do
            if #items < MAX_ITEMS then items[#items + 1] = item end
        end
    end
    local signature = #items > 0 and json.encode(items) or nil
    if signature == shown then return end
    shown = signature
    if signature then
        exports['cortex-lib']:showHelp(items, { compact = #items > 6 })
    else
        exports['cortex-lib']:hideHelp()
    end
end

-- items: { { label = 'Select', value = 'Enter' }, ... }, or nil to remove the layer.
function Admin.setHelpLayer(id, items)
    layers[id] = type(items) == 'table' and #items > 0 and items or nil
    render()
end
