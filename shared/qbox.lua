-- The same descriptors drive permissions, Classic handoff and the Panel forms.
QboxAdmin = { actions = {} }
local function field(name, label, catalog, min, max)
    return { name = name, label = label, catalog = catalog, type = min and 'number' or 'text', min = min, max = max }
end
local target = field('target', 'Player', 'players')
local amount = field('amount', 'Amount', nil, 1, 10000000)
local item = field('item', 'Item', 'items')
local count = field('amount', 'Quantity', nil, 1, 10000)
local function action(id, label, description, fields, capability, confirm, selfOnly)
    local entry = { id = 'qbx.' .. id, label = label, description = description, tab = 'qbx',
        type = 'action', framework = 'qbx', capability = capability, qbox = true,
        fields = fields or {}, confirm = confirm, selfOnly = selfOnly }
    QboxAdmin.actions[entry.id] = entry
    EsAdminActions.actions[#EsAdminActions.actions + 1] = entry
    Config.ActionPermissions[entry.id] = Config.ActionPermissions[entry.id] or ('cortex-admin.' .. entry.id)
end
EsAdminActions.tabs[#EsAdminActions.tabs + 1] = { id = 'qbx', label = 'Qbox', framework = 'qbx' }
Config.Permissions.qbx = Config.Permissions.qbx or 'cortex-admin.qbx'
action('giveVehicle', 'Give owned vehicle', 'Add a vehicle to the selected character’s garage. Retrieve it at that garage.',
    { target, field('model', 'Vehicle', 'vehicles'), field('garage', 'Garage', 'garages') }, 'ownedVehicles', true)
action('giveItem', 'Give inventory item', 'Browse every registered inventory item, including weapons and custom items.', { target, item, count }, 'inventory')
QboxAdmin.actions['qbx.giveItem'].permissionAlias = 'inventory.giveItem'
action('removeItem', 'Remove inventory item', 'Remove an exact quantity. Fails if the character does not have enough.', { target, item, count }, 'inventory', true)
action('openInventory', 'Inspect player inventory', 'Open the selected player’s inventory.', { target }, 'inventory')
action('clearInventory', 'Clear player inventory', 'Permanently remove every item from the selected player’s inventory.', { target }, 'inventory', true)
for _, account in ipairs({ 'Cash', 'Bank' }) do
    for _, operation in ipairs({ 'add', 'remove', 'set' }) do
        local value = field('amount', 'Amount', nil, operation == 'set' and 0 or 1, amount.max)
        action(operation .. account, operation:sub(1, 1):upper() .. operation:sub(2) .. ' ' .. account:lower(),
            'Update the character’s ' .. account:lower() .. ' balance through Qbox.', { target, value }, nil, operation ~= 'add')
    end
end
for _, group in ipairs({ 'Job', 'Gang' }) do
    for _, operation in ipairs({ 'set', 'add', 'remove', 'primary' }) do
        local fields = { target, field('group', group, group == 'Job' and 'jobs' or 'gangs') }
        if operation == 'set' or operation == 'add' then fields[#fields + 1] = field('grade', 'Grade', 'grades') end
        local labels = { set = 'Set primary ', add = 'Add ', remove = 'Remove ', primary = 'Switch primary ' }
        action(operation .. group, labels[operation] .. group:lower(),
            operation == 'set' and 'Set the primary membership using the server’s Qbox replacement policy.' or 'Manage Qbox character memberships.', fields, nil, operation == 'set' or operation == 'remove')
    end
end
action('dutyOn', 'Set on duty', 'Put the selected character on duty.', { target })
action('dutyOff', 'Set off duty', 'Take the selected character off duty.', { target })
for _, key in ipairs({ 'hunger', 'thirst', 'stress' }) do
    action(key, 'Set ' .. key, 'Update Qbox needs and the replicated player state.', { target, field('value', 'Value (0–100)', nil, 0, 100) })
end
action('resetNeeds', 'Restore needs', 'Fill hunger and thirst and clear stress.', { target })
action('grantLicense', 'Grant license', 'Enable a license already defined on this character.', { target, field('license', 'License', 'licenses') })
action('revokeLicense', 'Revoke license', 'Disable a license already defined on this character.', { target, field('license', 'License', 'licenses') }, nil, true)
action('saveCharacter', 'Save character data', 'Request Qbox to save the selected character’s current data.', { target })
action('inspectCharacter', 'Inspect character', 'Read citizen ID, money, memberships, duty, needs and licenses.', { target })
action('saveAppearance', 'Save current look as character', 'Make your current ped, face, hair, outfit and tattoos the active character appearance used on login.', {}, 'appearance', true, true)
action('restoreAppearance', 'Load saved character look', 'Replace your current look with the active appearance stored for this character.', {}, 'appearance', true, true)

function QboxAdmin.capabilities()
    local function started(resource) return GetResourceState(resource) == 'started' end
    local qbx = started('qbx_core')
    if not IsDuplicityVersion() then
        local caps = QboxAdmin.serverCapabilities or { hasQBX = false, framework = 'standalone' }
        if not qbx then return { hasQBX = false, framework = 'standalone' } end
        return caps
    end
    return { hasQBX = qbx, framework = qbx and 'qbx' or 'standalone',
        hasInventory = qbx and started('ox_inventory'), hasGarage = qbx and started('qbx_vehicles'),
        inventory = qbx and started('ox_inventory'),
        ownedVehicles = qbx and started('qbx_vehicles') and started('qbx_garages'),
        appearance = qbx and started('illenium-appearance') and started('oxmysql') }
end

function QboxAdmin.available(action)
    local caps = QboxAdmin.capabilities()
    return caps.hasQBX and (not action.capability or caps[action.capability] == true)
end
