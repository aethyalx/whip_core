-- ============================================
-- The settings page's Place (client/place_point.lua's PlacePoint)
-- ============================================
--
-- On a vec3 / vec4 entry with `place = true`, or `place = { model = 'prop or ped', ped = true }`
-- (html/js/wp/config.js): the panel steps aside, and what is placed comes back to it as an edit waiting for Apply
-- ('pointPlaced'), as "Use where I stand" does. Esc gives nothing back.

local busy = false

RegisterNUICallback('cfgPlacePoint', function(d, cb)
    cb('ok')
    if type(d) ~= 'table' or type(d.path) ~= 'string' or busy then return end
    busy = true
    local place = type(d.place) == 'table' and d.place or {}
    CreateThread(function()
        WhipPanelSuspend()
        local point = PlacePoint({ at = d.at, model = place.model, ped = place.ped == true, label = d.label })
        WhipPanelResume()
        busy = false
        if point then
            WhipPanelData(type(d.section) == 'string' and d.section or 'config', 'pointPlaced',
                { path = d.path, row = d.row, field = d.field, value = point })
            WhipPanelResult('Placed: Apply to keep it.', 'ok')
        end
    end)
end)
