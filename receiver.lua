--[[
    Radio Headless Simplifiée
    Joue une seule chanson prédéfinie sur commande Rednet.
    Commandes Rednet: "play", "stop", "status_request", "volume_up", "volume_down"
--]]

local api_base_url = "https://ipod-2to6magyna-uc.a.run.app/"
local version = "2.1"

rednet.open("back")

-- ###############################################################
-- ## À MODIFIER OBLIGATOIREMENT ##
-- Mettez ici l'ID de la vidéo YouTube que vous voulez jouer.
-- Exemple : pour "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
-- L'ID est "dQw4w9WgXcQ"

local PREDEFINED_SONG = {
    id = "dQw4w9WgXcQ", -- REMPLACEZ CECI
    name = "Never Gonna Give You Up", -- REMPLACEZ CECI (optionnel, pour l'affichage)
    artist = "Rick Astley" -- REMPLACEZ CECI (optionnel, pour l'affichage)
}
-- ###############################################################


-- --- Variables d'état ---
local playing = false
local volume = 1.5

-- --- Variables audio ---
local playing_id = nil
local last_download_url = nil
local playing_status = 0 -- 0=Pas prêt, 1=Prêt à décoder
local is_loading = false
local player_handle = nil
local start = nil
local size = nil
local decoder = require "cc.audio.dfpwm".make_decoder()
local needs_next_chunk = 0

-- --- Vérification des haut-parleurs ---
local speakers = { peripheral.find("speaker") }
if #speakers == 0 then
	print("Erreur: Aucun haut-parleur n'est connecté.")
	error("Vous devez connecter un haut-parleur à cet ordinateur.", 0)
end


---
-- BOUCLE AUDIO (Simplifiée)
---
function audioLoop()
	while true do
		-- 1. Si on doit jouer (playing = true)
		if playing then
			local thissongid = PREDEFINED_SONG.id
			
			-- 1a. Si la chanson n'est pas chargée, la télécharger
			if playing_id ~= thissongid then
				playing_id = thissongid
				last_download_url = api_base_url .. "?v=" .. version .. "&id=" .. textutils.urlEncode(playing_id)
				playing_status = 0
				needs_next_chunk = 1

				print("Chargement: " .. PREDEFINED_SONG.name)
				http.request({url = last_download_url, binary = true})
				is_loading = true
				os.queueEvent("audio_update") -- Réveille la boucle

			-- 1b. Si la chanson est téléchargée (status=1), la décoder
			elseif playing_status == 1 and needs_next_chunk == 1 then
				while true do
					local chunk = player_handle.read(size)
					
					-- Fin de la chanson
					if not chunk then
						print("Fini: " .. PREDEFINED_SONG.name)
						playing = false
						playing_id = nil
						is_loading = false
						player_handle.close()
						needs_next_chunk = 0
						break -- Sortir de la boucle de décodage
					
					-- Chunk suivant
					else
						if start then
							chunk, start = start .. chunk, nil
							size = size + 4
						end
				
						local buffer = decoder(chunk)
						
						-- Jouer sur les haut-parleurs (logique simplifiée)
						for _, speaker in ipairs(speakers) do
							local name = peripheral.getName(speaker)
							while not speaker.playAudio(buffer, volume) do
								local event, p1, p2, p3 = os.pullEvent()
                                if event == "speaker_audio_empty" and p2 == name then
                                    break -- Le buffer est vide, on peut envoyer le suivant
                                elseif event == "playback_stopped" then
                                    return -- Stoppé par rednet
                                end
							end
                            if not playing or playing_id ~= thissongid then break end
						end
						
						-- Si 'playing' est devenu faux (ordre "stop"), arrêter
						if not playing or playing_id ~= thissongid then
							break
						end
					end
				end
				os.queueEvent("audio_update") -- Réveille la boucle
			end
		end

		-- Attend un événement pour ne pas surcharger
		os.pullEvent("audio_update")
	end
end

---
-- BOUCLE HTTP (Simplifiée)
---
function httpLoop()
	while true do
		parallel.waitForAny(
			-- Succès: Le téléchargement de la chanson est prêt
			function()
				local event, url, handle = os.pullEvent("http_success")
				if url == last_download_url then
					print("Chargement terminé.")
					is_loading = false
					player_handle = handle
					start = handle.read(4)
					size = 16 * 1024 - 4
					playing_status = 1 -- Prêt à décoder
					os.queueEvent("audio_update")
				end
			end,
			-- Echec: Le téléchargement a raté
			function()
				local event, url = os.pullEvent("http_failure")	
				if url == last_download_url then
					print("Erreur: Echec du téléchargement.")
					is_loading = false
					playing = false
					playing_id = nil
					os.queueEvent("audio_update")
				end
			end
		)
	end
end

---
-- BOUCLE REDNET (Simplifiée)
---
function rednetLoop()
    while true do
        local sender_id, message, protocol = rednet.receive()
        print("Commande reçue: " .. message)

        if message == "play" then
            if not playing then
                playing = true
                os.queueEvent("audio_update") -- Réveille la boucle audio
                rednet.send(sender_id, "OK: Lecture démarrée.")
            end

        elseif message == "pause" or message == "stop" then
            if playing then
                playing = false
                -- Force l'arrêt des haut-parleurs
                for _, speaker in ipairs(speakers) do
                    speaker.stop()
                end
                os.queueEvent("playback_stopped") -- Envoie un signal pour arrêter la boucle audio
                playing_id = nil -- Force le re-téléchargement si "play" est renvoyé
                is_loading = false
                os.queueEvent("audio_update")
                rednet.send(sender_id, "OK: Lecture arrêtée.")
            end

        elseif message == "status_request" then
            local status_msg = "Chanson: " .. PREDEFINED_SONG.name
            if is_loading then
                status_msg = status_msg .. " | Statut: Chargement..."
            elseif playing then
                status_msg = status_msg .. " | Statut: En lecture"
            else
                status_msg = status_msg .. " | Statut: Arrêté"
            end
            rednet.send(sender_id, status_msg)
        
        elseif message == "volume_up" then
            volume = math.min(volume + 0.25, 3.0)
            rednet.send(sender_id, "Volume: " .. math.floor(volume / 3 * 100) .. "%")
        
        elseif message == "volume_down" then
            volume = math.max(volume - 0.25, 0.0)
            rednet.send(sender_id, "Volume: " .. math.floor(volume / 3 * 100) .. "%")
            
        else
            rednet.send(sender_id, "Commande inconnue (play, stop, status_request).")
        end
    end
end

-- ---
-- DÉMARRAGE
-- ---
print("Radio Headless Démarrée.")
print("Chanson: " .. PREDEFINED_SONG.name)
print("En attente de commandes Rednet...")
parallel.waitForAny(audioLoop, httpLoop, rednetLoop)