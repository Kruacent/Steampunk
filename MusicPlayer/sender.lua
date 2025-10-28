-- Script "sender" simplifiÃ© pour la radio

--- Ã MODIFIER ---
local ipod_id = 4
-------------------

local args = { ... }
if #args == 0 then
    print("Usage: sender <commande>")
    print("Commandes: play, stop, status, vol_up, vol_down")
    return
end

local command = args[1]
local msg_to_send = ""

if command == "play" then
    msg_to_send = "play"
elseif command == "stop" or command == "pause" then
    msg_to_send = "stop"
elseif command == "status" then
    msg_to_send = "status_request"
elseif command == "vol_up" then
    msg_to_send = "volume_up"
elseif command == "vol_down" then
    msg_to_send = "volume_down"
else
    print("Commande inconnue.")
    return
end

rednet.open("back")
rednet.send(ipod_id, msg_to_send)

-- Attendre une rÃ©ponse
local sender_id, message = rednet.receive(3) -- Attend 3 secondes
if sender_id then
    print("[RÃ©ponse]: " .. message)
else
    print("(Pas de rÃ©ponse reÃ§ue.)")
end