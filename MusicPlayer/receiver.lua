--[[
    Lecteur de Musique Headless v4 (ID Direct)
    Utilise le serveur Node.js V4.
--]]

local api_base_url = "http://omergs.com:3000/"
local version = "2.1"

rednet.open("back")

-- --- Variables d'état ---
local playing = false
local volume = 1.5
local queue = {}
local now_playing = nil

-- --- Variables audio ---
local playing_id = nil
local last_download_url = nil
local playing_status = 0
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
-- BOUCLE AUDIO (Gère la lecture, la pause, et la file d'attente)
---
function audioLoop()
	while true do
		-- 1. Si on doit jouer ET qu'une chanson est chargée
		if playing and now_playing then
			local thisnowplayingid = now_playing.id
			
			-- 1a. Si la chanson n'est pas chargée, la télécharger
			if playing_id ~= thisnowplayingid then
				playing_id = thisnowplayingid
                
                -- C'EST ICI QUE L'ID EST ENVOYÉ
				last_download_url = api_base_url .. "?v=" .. version .. "&id=" .. textutils.urlEncode(playing_id)
				playing_status = 0
				needs_next_chunk = 1

				print("Chargement: " .. now_playing.name)
				http.request({url = last_download_url, binary = true})
				is_loading = true
				os.queueEvent("audio_update")

			-- 1b. Si la chanson est téléchargée (status=1), la décoder
			elseif playing_status == 1 and needs_next_chunk == 1 then
				while true do
					local chunk = player_handle.read(size)
					
					-- Fin de la chanson
					if not chunk then
						print("Fini: " .. now_playing.name)
						if player_handle then player_handle.close(); player_handle = nil; end
						
						if #queue > 0 then
							now_playing = queue[1]
							table.remove(queue, 1)
							playing_id = nil
						else
							now_playing = nil
							playing = false
							playing_id = nil
							is_loading = false
							print("File d'attente terminée.")
						end
						needs_next_chunk = 0
						break
					
					-- Chunk suivant à décoder
					else
						if start then
							chunk, start = start .. chunk, nil
							size = size + 4
						end
				
						local buffer = decoder(chunk)
						
						-- Jouer sur les haut-parleurs
						local fn = {}
						for i, speaker in ipairs(speakers) do 
							fn[i] = function()
								local name = peripheral.getName(speaker)
								if #speakers > 1 then
									if speaker.playAudio(buffer, volume) then
										parallel.waitForAny(
											function() repeat until select(2, os.pullEvent("speaker_audio_empty")) == name end,
											function() os.pullEvent("playback_stopped"); return end
										)
										if not playing or playing_id ~= thisnowplayingid then return end
									end
								else
									while not speaker.playAudio(buffer, volume) do
										parallel.waitForAny(
											function() repeat until select(2, os.pullEvent("speaker_audio_empty")) == name end,
											function() os.pullEvent("playback_stopped"); return end
										)
										if not playing or playing_id ~= thisnowplayingid then return end
									end
								end
								if not playing or playing_id ~= thisnowplayingid then return end
							end
						end
						pcall(parallel.waitForAll, table.unpack(fn))
						
						if not playing or playing_id ~= thisnowplayingid then
							break
						end
					end
				end
				os.queueEvent("audio_update")
			end
		
		-- 2. Si on doit jouer, mais rien n'est chargé, et la file n'est pas vide
		elseif playing and not now_playing and #queue > 0 then
			now_playing = queue[1]
			table.remove(queue, 1)
			playing_id = nil
			is_loading = false
			print("Lecture (file): " .. now_playing.name)
			os.queueEvent("audio_update")

		elseif playing and not now_playing and #queue == 0 then
			playing = false
		end

		os.pullEvent("audio_update")
	end
end

---
-- BOUCLE HTTP (Simplifiée : ne gère QUE le téléchargement)
---
function httpLoop()
	while true do
		parallel.waitForAny(
			-- Succès (téléchargement de chanson)
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
				else
                    if handle then handle.close() end
                end
			end,
			-- Echec (téléchargement de chanson)
			function()
				local event, url = os.pullEvent("http_failure")	
				if url == last_download_url then
					print("Erreur: Echec du téléchargement.")
					is_loading = false
					playing = false
					playing_id = nil
					now_playing = nil
					os.queueEvent("audio_update")
				end
			end
		)
	end
end

---
-- BOUCLE REDNET (Modifiée pour accepter des ID)
---
function rednetLoop()
    while true do
        local sender_id, message, protocol = rednet.receive()
        print("Commande reçue: " .. message)

		local command, video_id = string.match(message, "([^:]+):(.+)")
        if command == nil then
            command = message
        end

        -- --- COMMANDES D'AJOUT PAR ID ---
        if (command == "add_id" or command == "play_id_now") and video_id then
            local song = {
                id = video_id,
                name = "ID: " .. video_id,
                artist = "Ajouté à distance"
            }
            
            if command == "play_id_now" then
                print("Lecture immédiate: " .. video_id)
                for _, speaker in ipairs(speakers) do speaker.stop() end
                os.queueEvent("playback_stopped")
                if player_handle then player_handle.close(); player_handle = nil; end
                
                now_playing = song
                queue = {}
                playing = true
                playing_id = nil
                os.queueEvent("audio_update")
                rednet.send(sender_id, "OK: Lecture immédiate " .. video_id)
                
            elseif command == "add_id" then
                print("Ajout file: " .. video_id)
                table.insert(queue, song)
                rednet.send(sender_id, "OK: Ajouté à la file.")
                
                if not playing and not now_playing then
                    playing = true
                    os.queueEvent("audio_update")
                end
            end

        -- --- COMMANDES DE LECTURE ---
        elseif command == "play" then
            if not playing and (now_playing ~= nil or #queue > 0) then
                playing = true
                os.queueEvent("audio_update")
                rednet.send(sender_id, "OK: Lecture démarrée.")
            end

        elseif command == "pause" then
            if playing then
                playing = false
                for _, speaker in ipairs(speakers) do speaker.stop() end
                os.queueEvent("playback_stopped")
                os.queueEvent("audio_update")
                rednet.send(sender_id, "OK: Lecture en pause.")
            end

        elseif command == "skip" then
            if #queue > 0 or now_playing then
                print("Skip...")
                for _, speaker in ipairs(speakers) do speaker.stop() end
                os.queueEvent("playback_stopped")
                if player_handle then player_handle.close(); player_handle = nil; end
                
                if #queue > 0 then
                    now_playing = queue[1]
                    table.remove(queue, 1)
                    playing_id = nil
                    playing = true
                else
                    now_playing = nil
                    playing = false
                    playing_id = nil
                    print("File vide.")
                end
                os.queueEvent("audio_update")
                rednet.send(sender_id, "OK: Piste suivante.")
            else
                rednet.send(sender_id, "File vide, rien à passer.")
            end

        elseif command == "status_request" then
            local status_msg = "Statut: "
            if is_loading then status_msg = status_msg .. "Chargement..."
            elseif playing then status_msg = status_msg .. "En lecture"
            elseif now_playing then status_msg = status_msg .. "En pause"
            else status_msg = status_msg .. "Arrêté" end
            
            if now_playing then status_msg = status_msg .. " | Actuel: " .. now_playing.name end
            status_msg = status_msg .. " | File: " .. #queue .. " chansons"
            rednet.send(sender_id, status_msg)
        
        elseif command == "volume_up" then
            volume = math.min(volume + 0.25, 3.0)
            rednet.send(sender_id, "Volume: " .. math.floor(volume / 3 * 100) .. "%")
        
        elseif command == "volume_down" then
            volume = math.max(volume - 0.25, 0.0)
            rednet.send(sender_id, "Volume: " .. math.floor(volume / 3 * 100) .. "%")
            
        else
            rednet.send(sender_id, "Commande inconnue.")
        end
    end
end

-- ---
-- DÉMARRAGE
-- ---
print("Lecteur Headless v4 (ID Direct) Démarré.")
print("En attente de commandes Rednet...")
parallel.waitForAny(audioLoop, httpLoop, rednetLoop)