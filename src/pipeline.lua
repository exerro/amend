
--[[ Stages
0
	get_stream()
1
	parse()
2
	transform()
3
	compile()
4
]]

local util = require "util"
local warning = require "warning"
local stream = require "parsing.stream"
local ID = 0
local pipeline = {}

local function applies_to( plugin, mode )
	if mode == "*" then
		return true
	end
	for pmode in plugin.mode:gmatch "%s*([^;,%s][^;,]*)" do
		if pmode == "*" or mode:find( "^" .. util.escape_patterns( pmode ) ) then
			return true
		end
	end
	return false
end

function pipeline:new( uri, mode, build, host )
	ID = ID + 1
	local p = setmetatable( {
		ID = ID,
		uri = uri,
		mode = mode,
		build = build,
		host = host,
		plugins = {},
		meta = {},
		stage = 0,

		-- plugin callbacks
		read_all_required = false,
		read_all_callbacks = {},
		directives = {},
		directive_callbacks = {},
		lexer_callbacks = {
			ignore = {},
		},
		parse_node_callbacks = {},
		transform_node_callbacks = {},
		transform_ast_clalbacks = {},
	}, { __index = self } )

	for i = 1, #build.plugins do
		if applies_to( build.plugins[i], mode ) then
			self:initialise_plugin( build.plugins[i] )
		end
	end

	return p
end

function pipeline:initialise_plugin( plugin )
	self.meta[plugin.name] = plugin.state( self )
	self.plugins[#self.plugins + 1] = plugin
	self.read_all_required = self.read_all_required or plugin.file_read_all

	for i = 1, #plugin.directive_list do
		local directive = plugin.name .. "/" .. plugin.directive_list[i]

		self.directives[#self.directives + 1] = directive
		self.directive_callbacks[directive] = plugin.directive_callbacks[i]
		self.directives[#self.directives + 1] = plugin.directive_list[i]
		self.directive_callbacks[plugin.directive_list[i]] = plugin.directive_callbacks[i]
	end

	for i = 1, #plugin.lexer_callbacks.ignore do
		self.lexer_callbacks.ignore[#self.lexer_callbacks.ignore + 1] = plugin.lexer_callbacks.ignore[i]
	end

	for i = 1, #plugin.parse_node_callbacks do
		self.parse_node_callbacks[#self.parse_node_callbacks + 1] = plugin.parse_node_callbacks[i]
	end

	for i = 1, #plugin.transform_node_callbacks do
		self.transform_node_callbacks[#self.transform_node_callbacks + 1] = plugin.transform_node_callbacks[i]
	end

	for i = 1, #plugin.transform_ast_callbacks do
		self.transform_ast_callbacks[#self.transform_ast_callbacks + 1] = plugin.transform_ast_callbacks[i]
	end
end

function pipeline:get_stream()
	if self.read_all_required then
		local handle = util.open_uri_handle( self.uri )

		if handle then
			local content = handle:read "*a"
			handle:close()

			for i = 1, #self.plugins do
				if self.plugins[i].file_read_all then
					content = self.plugins[i].file_read_modifier( self, content )
				end
			end

			self.stage = 1
			return stream.stringstream:new( content, 1 )
		else
			warning.warn( warning.URI_HANDLE_OPEN_FAIL, "failed to open handle for URI '" .. self.uri .. "'" )
			return nil
		end
	else
		local s = stream.filestream:new( self.uri )

		if s then
			return s
		else
			warning.warn( warning.URI_HANDLE_OPEN_FAIL, "failed to open handle for URI '" .. self.uri .. "'" )
			return nil
		end
	end

	return stream
end

return pipeline
