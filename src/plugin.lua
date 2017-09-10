
local warning = require "warning"

local plugin = {}

local function plugin_environment( name )
	local env = {}
	local plugin = {
		name = name,
		mode = "*",
		state = function() return {} end,
		file_lookup_callbacks = {},
		file_read_all = false,
		file_read_modifier = nil,
		directive_list = {},
		directive_callbacks = {},
		lexer_callbacks = {
			ignore = {}
		},
		parse_node_callbacks = {},
		transform_node_callbacks = {},
		transform_ast_callbacks = {},
		compile_node_callbacks = {},
		compile_header_callbacks = {},
		compile_footer_callbacks = {},
	}

	env.plugin = plugin

	plugin.directives = setmetatable( {}, { __newindex = function( s, k, v )
		plugin.directive_list[#plugin.directive_list + 1] = k
		plugin.directive_callbacks[k] = v
	end } )

	plugin.lexer = setmetatable( {}, { __newindex = function( s, k, v )
		if k == "ignore" then
			plugin.lexer_callbacks.ignore[#plugin.lexer_callbacks.ignore + 1] = v
		else
			return error( "unsupported hook '" .. tostring( k ) .. "'" )
		end
	end } )

	plugin.transform = setmetatable( {}, { __newindex = function( s, k, v )
		if k == "node" then
			plugin.transform_node_callbacks[#plugin.transform_node_callbacks + 1] = v
		elseif k == "ast" then
			plugin.transform_ast_callbacks[#plugin.transform_ast_callbacks + 1] = v
		else
			return error( "unsupported mode '" .. tostring( k ) .. "'" )
		end
	end } )

	plugin.compile = setmetatable( {}, { __newindex = function( s, k, v )
		if k == "node" then
			plugin.compile_node_callbacks[#plugin.compile_node_callbacks + 1] = v
		elseif k == "header" then
			plugin.compile_header_callbacks[#plugin.compile_header_callbacks + 1] = v
		elseif k == "footer" then
			plugin.compile_footer_callbacks[#plugin.compile_footer_callbacks + 1] = v
		else
			return error( "unsupported mode '" .. tostring( k ) .. "'" )
		end
	end } )

	setmetatable( plugin, { __newindex = function( s, k, v )
		if k == "lookup" then
			plugin.file_lookup_callbacks[#plugin.file_lookup_callbacks + 1] = v
		elseif k == "parse" then
			plugin.parse_node_callbacks[#plugin.parse_node_callbacks + 1] = v
		end
	end } )

	return setmetatable( env, getfenv and getfenv() or _ENV ), plugin
end

local function plugin_loader( content, name )
	local env, plugin_data = plugin_environment( name )
	local f, err = (load or loadfile)( content, "[plugin] " .. name, nil, env )

	if not f then
		return warning.warn( warning.PLUGIN_ERR, "failed to load plugin '" .. name .. "': " .. err )
	elseif not load then
		setfenv( f, env )
	end

	local ok, err = pcall( f )

	if not ok then
		return warning.warn( warning.PLUGIN_ERR, "failed to load plugin '" .. name .. "': " .. err )
	end

	return plugin_data
end

function plugin.load( file, paths )
	local name = file:gsub( ".+/", "" ):gsub( "%.%w+$", "", 1 )

	for i = 1, #(paths or {}) do
		local path = (paths[i] or ".") .. "/" .. file
		local h = io.open( path, "r" ) -- TODO: change to support URLs

		if h then
			local content = h:read "*a"
			h:close()

			return plugin_loader( content, name )
		end
	end

	warning.warn( warning.PLUGIN_ERR, "failed to load plugin '" .. name .. "': file not found '" .. file .. "'" )
end

return plugin
