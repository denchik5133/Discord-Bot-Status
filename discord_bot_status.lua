/***
 *   @script        Discord Bot Status
 *   @version       1.0.0
 *   @release_date  14/12/2024
 *   @author        denchik
 *   @contact       Discord: denchik_gm
 *                  Steam: https://steamcommunity.com/profiles/76561198405398290/
 *                  GitHub: https://github.com/denchik5133
 *                
 *   @description   This script is designed for Garry's Mod (GMod) using Lua to update the status of
 *					a Discord bot with server information. It retrieves the current online players,
 *					server details, and sends this information as an embed message to a specified Discord channel.
 *					The bot automatically updates the message at defined intervals and keeps track of daily and 
 *					all-time player records.
 *
 *   @usage         To use this script, place it in a Lua file within your Garry's Mod server, for example at 
 *   				`discord_bot_status/lua/autorun/server/discord_bot_status.lua`. 
 *   				Ensure you have the required dependencies and a valid Discord bot token. 
 *   				Configure the `config` table with your bot's token, guild ID, and channel ID. 
 *   				Run the script in the GMod environment to start sending updates.
 *   				The bot will post updates every specified interval (default is 60 seconds).
 *   				Make sure to grant the proper permissions for your bot in the Discord server.
 *
 *   @license       MIT License
 *   @notes         For feature requests or contributions, please open an issue on GitHub.
 */



if (LuaRefreshController or 0) > CurTime() then return end
LuaRefreshController = CurTime() + 0.5


-- Bot Configuration
local config = {
	interval = 60, -- How many seconds will the message be updated?
	server_id = 1, -- Each next server should have its own server_id (in order 1, 2, 3, etc.)
	embed_color = Color(255, 165, 0), -- Orange color used for embed messages
	log_level = 1, -- 0 = nothing, 1 = errors, 2 = all requests
	token = 'YOUR_BOT_TOKEN', -- bot token
	guild = 'YOUR_GUILD_ID', -- guild id
	channel = 'YOUR_CHANNEL_ID', -- channel id
	version = 10, -- API version
	servername = 'Server Information: ', -- Server name here
	endpoints = {
		message = '/channels/%s/messages/%s', -- Endpoint for retrieving a specific message by channel and message ID
		messages = '/channels/%s/messages', -- Endpoint for retrieving all messages in a channel
		me = '/users/@me' -- Endpoint for retrieving information about the authenticated user (the bot)
	}
}


local encode = util.TableToJSON
local decode = util.JSONToTable
local debug_start = string.format('\27[38;2;%d;%d;%dm', 46, 204, 113) .. '[DiscordBot] \27[0m'


--- Logs messages to the console based on the log level.
-- @param level (number): The log level of the message.
-- @param msg (string): The message to log.
local function log(level, msg)
	if (level > config.log_level) then return end

	Msg(debug_start)
	while #msg > 0 do
		Msg(msg:sub(1, 1023))
		msg = msg:sub(1024)
	end
	Msg('\n')
end


-- Import the reqwest library for making HTTP requests
require('reqwest')
local reqwest = reqwest

-- Create a base endpoint for Discord API using the configured version
local endpoint = setmetatable({ base = 'https://discord.com/api/v' .. config.version }, {
	__index = function(self, endpoint)
		-- Return the full URL for the specified endpoint
		return self.base .. config.endpoints[endpoint]
	end
})


-- Define the http object for making GET and POST requests
local http
http = setmetatable({
	-- Function to make a GET request
	get = function(url, headers, payload)
		return http('GET', url, headers, payload)
	end,
	-- Function to make a POST request
	post = function(url, headers, payload)
		return http('POST', url, headers, payload)
	end
}, {
	__call = function(_, method, url, headers, payload)
		-- Get the current coroutine for asynchronous handling
		local co = coroutine.running()
		reqwest({
			method = method, -- HTTP method (GET or POST)
			url = url, -- The URL to make the request to
			headers = headers, -- Optional headers for the request
			body = payload, -- The body of the request (for POST)
			success = function(code, body, headers)
				-- Resume the coroutine on a successful request
				local succ, err = coroutine.resume(co, true, body, code, headers)
				if (succ == false) then log(1, 'ERROR http request resume '.. err) end
			end,
			failed = function(reason)
				-- Resume the coroutine on a failed request
				local succ, err = coroutine.resume(co, false, reason)
				if (succ == false) then log(1, 'ERROR http request resume '.. err) end
			end,
			timeout = 5 -- Set a timeout for the request (in seconds)
		})

		-- Yield the coroutine until the request is completed
		return coroutine.yield()
	end
})


-- Gets the server address in "IP:port" format.
-- @return: A string representing the server address in "IP:port" format.
local function getAddress()
    -- Get the IP and port string from the settings
    local hostIP = GetConVarString('hostip')
    local hostPort = GetConVarString('hostport')
    
    -- Convert the IP string to a number
    local address = tonumber(hostIP)

    -- If no address is specified, return the default local address
    if (not address) then
        return '127.0.0.1:' .. hostPort
    end

    -- Break the address into octets
    local ip = {
        bit.rshift(bit.band(address, 0xFF000000), 24),
        bit.rshift(bit.band(address, 0x00FF0000), 16),
        bit.rshift(bit.band(address, 0x0000FF00), 8),
        bit.band(address, 0x000000FF)
    }

    -- Combine the octets into a string and add the port
    return table.concat(ip, '.') .. ':' .. hostPort
end



local api = {}
do
	--- Makes an API request to Discord.
	-- @param method (string): The HTTP method (GET, POST, etc.).
	-- @param endpoint (string): The API endpoint.
	-- @param payload (table): The data to send with the request.
	-- @param silent (boolean): If true, suppresses error logging.
	-- @return (table, number, table): The response body, status code, and headers.
	function api.request(method, endpoint, payload, silent)
		local payloadStr = payload and encode(payload, true) or nil
    	log(2, 'request ' .. method .. ' ' .. endpoint .. (payloadStr and ' - ' .. payloadStr or ''))

		if payload then
			payload = encode(payload, true)
			log(2, 'request '.. method ..' '.. endpoint ..' - '.. payload)
		else
			log(2, 'request '.. method ..' '.. endpoint)
		end

		local success, body_or_reason, code, headers = http(method, endpoint, {
			Authorization = 'Bot ' .. config.token,
			['User-Agent'] = 'incredible-gmod.ru',
			['X-RateLimit-Precision'] = 'millisecond',
			['Content-Type'] = payload and 'application/json' or nil,
			['Content-Length'] = payload and #payload or nil
		}, payload)

		if success then
			if (code == 200) then
				return decode(body_or_reason), code, headers
			elseif (silent ~= true) then
				log(1, 'ERROR '.. code ..' - '.. body_or_reason ..' : '.. method ..' '.. endpoint)
			end
		else
			log(1, 'ERROR '.. body_or_reason ..' : '.. method ..' '.. endpoint)
		end
	end

	--- Retrieves messages from a specified channel.
    -- @param channel_id (string): The ID of the channel to retrieve messages from.
    -- @param silent (boolean): If true, suppresses error logging.
    -- @return (table|nil): The list of messages, or nil on failure.
	function api.getMessages(channel_id, silent)
		return api.request('GET', endpoint.messages:format(channel_id), nil, silent)
	end

	--- Retrieves a specific message from a channel.
    -- @param channel_id (string): The ID of the channel.
    -- @param message_id (string): The ID of the message to retrieve.
    -- @param silent (boolean): If true, suppresses error logging.
    -- @return (table|nil): The message data, or nil on failure.
	function api.getMessage(channel_id, message_id, silent)
		return api.request('GET', endpoint.message:format(channel_id, message_id), nil, silent)
	end

	--- Sends a message to a specified channel.
    -- @param channel_id (string): The ID of the channel to send the message to.
    -- @param payload (table): The message content.
    -- @param silent (boolean): If true, suppresses error logging.
    -- @return (table|nil): The response from the API, or nil on failure.
	function api.sendMessage(channel_id, payload, silent)
		return api.request('POST', endpoint.messages:format(channel_id), payload, silent)
	end

	--- Edits a specific message in a channel.
    -- @param channel_id (string): The ID of the channel.
    -- @param message_id (string): The ID of the message to edit.
    -- @param payload (table): The new content for the message.
    -- @param silent (boolean): If true, suppresses error logging.
    -- @return (table|nil): The response from the API, or nil on failure.
	function api.editMessage(channel_id, message_id, payload, silent)
		return api.request('PATCH', endpoint.message:format(channel_id, message_id), payload, silent)
	end

	--- Retrieves information about the authenticated user (the bot).
    -- @param silent (boolean): If true, suppresses error logging.
    -- @return (table|nil): The user data, or nil on failure.
	function api.me(silent)
		return api.request('GET', endpoint.me, nil, silent)
	end
end


--- Creates a timer that runs a callback function at specified intervals.
-- @param name (string): The name of the timer.
-- @param interval (number): The time interval in seconds.
-- @param cback (function): The callback function to run.
local function timerCor(name, interval, cback)
	local run = coroutine.create(function()
		while true do
			cback()
			coroutine.yield()
		end
	end)

	local function go()
		local success, err = coroutine.resume(run)
		if (success == false) then log(1, 'ERROR timer resume '.. err) end
	end

	go()
	timer.Create(name, interval, 0, go)
end


--- Formats a duration in seconds into a string in HH:MM:SS format.
-- @param seconds (number): The duration in seconds.
-- @return (string): The formatted time string.
local function formatTime(seconds)
    if (not seconds or seconds <= 0) then return '00:00' end
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds / 60) % 60
    seconds = seconds % 60
    return hours > 0 and string.format('%.2i:%.2i:%.2i', hours, minutes, seconds) or string.format('%.2i:%.2i', minutes, seconds)
end


-- Check if the 'discord_message_id.txt' file exists and read its content; if it doesn't exist, set message_id to nil
local message_id = file.Exists('discord_message_id.txt', 'DATA') and file.Read('discord_message_id.txt', 'DATA') or nil

-- Convert RGB color values from the config to a single integer for embed color format
-- This combines red, green, and blue values into a single number using bitwise operations
local embed_color = bit.bor(bit.lshift(config.embed_color.r, 16) --[[ Shift red value to the left by 16 bits ]], bit.lshift(config.embed_color.g, 8) --[[ Shift green value to the left by 8 bits ]], config.embed_color.b --[[ Leave blue value as is ]])

-- Define the UTC offset for the local timezone (3 hours in seconds)
local msk_utc_offset = 3 * 60 * 60 -- 3 hours

-- Initialize daily_record to 0 and get the current day of the month in UTC
local daily_record, cur_day = 0, os.date('!*t', os.time() + msk_utc_offset).day

-- Check if the 'online_player_record.txt' file exists and read its content; if it doesn't exist, set total_record to 0
local total_record = file.Exists('online_player_record.txt', 'DATA') and file.Read('online_player_record.txt', 'DATA') or 0

-- Get the current date and time in the specified format, adjusted for the UTC offset
local last_update_time = os.date('%Y-%m-%d %H:%M:%S', os.time() + msk_utc_offset)


--- Creates an embed message for Discord with server information.
-- @param embeds (table): The existing embed data to append to (optional).
-- @return (table): The constructed embed message data.
local function createEmbed(embeds)
	local players = {}
	for i, ply in ipairs(player.GetHumans()) do
		players[i] = ply.GetUTimeSessionTime and (ply:Nick() ..': '.. formatTime(ply:GetUTimeSessionTime())) or ply:Nick()
	end

	local day = os.date('!*t', os.time() + msk_utc_offset).day
	if (day ~= cur_day) then
		cur_day = day
		daily_record = 0
	end
	daily_record = math.max(daily_record, #player.GetHumans())

	local new_total = math.max(total_record, #player.GetHumans())
	if (new_total ~= total_record) then
		total_record = new_total
		file.Write('online_player_record.txt', total_record)
	end

	embeds = embeds or {}
	embeds[config.server_id] = {
		color = embed_color,
		author = {
			name = config.servername .. getAddress(),
			icon_url = 'https://i.imgur.com/eYX4Vr2.png'
		},
		fields = {
			{ name = 'Name', value = '`' .. GetHostName() .. '`', inline = true },
			{ name = 'Gamemode', value = '`' .. gmod.GetGamemode()['Name'] .. '`', inline = true },
			{ name = 'Map', value = '`' .. game.GetMap() .. '`', inline = true },
			{ name = 'Current online', value = '`' .. #player.GetHumans() ..'/'.. game.MaxPlayers() .. '`', inline = true },
			{ name = 'Record online for today', value = '`' .. daily_record .. '`', inline = true },
			{ name = 'The all-time online record', value = '`' .. total_record .. '`', inline = true },
			{ name = 'Players List', value = '```\n'.. table.concat(players, '\n') ..'\n```', inline = true }
		},
		footer = {
			icon_url = 'https://i.imgur.com/E41l0Pk.png',
			text = 'Join Discord: https://discord.gg/CND6B5sH3j ● Last updated ' .. last_update_time
		},
	}

	return embeds
end


--- Updates an existing message with new embed data.
-- @param msg (table): The message object to update.
local function updateMessage(msg)
	last_update_time = os.date('%Y-%m-%d %H:%M:%S', os.time() + msk_utc_offset) -- Updating the time of the last update
	api.editMessage(config.channel, msg.id, { embeds = createEmbed(msg.embeds) })
end


--- Creates a new message in the specified channel.
local function createMessage()
	last_update_time = os.date('%Y-%m-%d %H:%M:%S', os.time() + msk_utc_offset) -- Set the time when creating a message
	api.sendMessage(config.channel, { embeds = createEmbed() })
end


--- Retrieves information about the authenticated user (the bot).
local me
coroutine.wrap(function() me = api.me() end)()


--- Timer that periodically updates the Discord bot status.
timerCor('DiscordBotStatus', config.interval, function()
	local msg
	if message_id then
		msg = api.getMessage(config.channel, message_id, true)
		if msg then
			updateMessage(msg)
			return
		end
	end

	local messages = api.getMessages(config.channel, true)
	if (messages and #messages > 0) then
		for _, message in ipairs(messages) do
			if (message.author.id == me.id) then
				message_id = message.id
				file.Write('discord_message_id.txt', message_id)
				updateMessage(message)
				return
			end
		end
	end

	createMessage()
end)
