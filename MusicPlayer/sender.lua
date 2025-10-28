-- Script pour la télécommande (à enregistrer sous "sender")

--- À MODIFIER ---
-- Mettez ici l'ID Rednet de votre iPod (le receiver).
local ipod_id = 6 -- !! CHANGEZ CECI PAR L'ID DU RECEIVER !!
-------------------

local args = { ... }

if #args == 0 then
    print("Usage: sender <commande> [argument]")
    print("Commandes:")
    print("  play, pause, skip, status, vol_up, vol_down")
    print("  add <recherche>")
    print("  next <recherche>")
    print("  now <recherche>")
    return
end

local command = args[1]
rednet.open("back")
local msg_to_send = ""

-- Gérer les commandes avec arguments (recherche)
if command == "add" or command == "next" or command == "now" then
    if #args < 2 then
        print("Erreur: Il faut un terme de recherche.")
        print("Usage: sender " .. command .. " <nom de la musique>")
        return
    end
    
    -- Recombine tous les arguments après la commande
    local query_parts = {}
    for i = 2, #args do
        table.insert(query_parts, args[i])
    end
    local query = table.concat(query_parts, " ")
    
    -- Traduire en commande pour le receiver
    if command == "add" then
        msg_to_send = "add_to_queue:" .. query
    elseif command == "next" then
        msg_to_send = "play_next:" .. query
    elseif command == "now" then
        msg_to_send = "play_now:" .. query
    end
    
    print("Envoi de la recherche '" .. query .. "'...")

else
    -- Gérer les commandes simples
    if command == "play" then
        msg_to_send = "play"
    elseif command == "pause" then
        msg_to_send = "pause"
    elseif command == "skip" then
        msg_to_send = "skip"
    elseif command == "status" then
        msg_to_send = "status_request"
    elseif command == "vol_up" then
        msg_to_send = "volume_up"
    elseif command == "vol_down" then
        msg_to_send = "volume_down"
    else
        print("Commande inconnue: " .. command)
        return
    end
    print("Envoi de la commande '" .. msg_to_send .. "'...")
end

-- Envoyer le message final
rednet.send(ipod_id, msg_to_send)

-- Écouter une réponse
local sender_id, message = rednet.receive(5) -- Attend 5 secondes

if sender_id then
    print("[Réponse]: " .. message)
else
    print("(Pas de réponse reçue, commande envoyée.)")
end