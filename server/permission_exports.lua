-- Server-only permission query. Keep consumers on the same policy as the admin menu.
exports('CanOpenMenu', function(playerId)
    if type(playerId) ~= 'number' or playerId % 1 ~= 0 or playerId <= 0 or playerId == math.huge then return false end
    return EsAdminServer.canOpenMenu(playerId) == true
end)

-- Use the action policy, including configured ACEs and QBX roles. Opening the
-- menu alone does not authorize destructive actions.
exports('CanDeleteVehicle', function(playerId)
    if type(playerId) ~= 'number' or playerId % 1 ~= 0 or playerId <= 0 or playerId == math.huge then return false end
    return EsAdminServer.hasPermission(playerId, 'vehicle.delete') == true
end)
