
local util = require "util"
local warning = require "warning"
local ID = 0
local pipeline = {}

local function applies_to( plugin, mode )
	if mode == "*" then
		return true
	end
	for pmode in plugin.mode:gmatch "%s*([^;,%s][^;,]*)" do
		if pmode == "*" or pmode == mode then
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
		compile_node_callbacks = {},
		compile_header_callbacks = {},
		compile_footer_callbacks = {},
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

	if plugin.file_read_all then
		self.read_all_callbacks[#self.read_all_callbacks + 1] = plugin.file_read_modifier
	end

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

	for i = 1, #plugin.compile_node_callbacks do
		self.compile_node_callbacks[#self.compile_node_callbacks + 1] = plugin.compile_node_callbacks[i]
	end

	for i = 1, #plugin.compile_header_callbacks do
		self.compile_header_callbacks[#self.compile_header_callbacks + 1] = plugin.compile_header_callbacks[i]
	end

	for i = 1, #plugin.compile_footer_callbacks do
		self.compile_footer_callbacks[#self.compile_footer_callbacks + 1] = plugin.compile_footer_callbacks[i]
	end
end

function pipeline:get_handle()
	local max_weight = -math.huge
	local max_weight_mode = nil
	local max_weight_uri = nil

	local URIs = self.build:get_URI_list( self.filename )

	for i = 1, #URIs do
		local obj = URIs[i]

		if obj.weight > max_weight then
			max_weight = obj.weight
			max_weight_uri = obj.path
			max_weight_mode = obj.mode
		end
	end

	if not max_weight_uri then
		return warning.error( warning.PIPELINE_HANDLE_ERR, "failed to get handle for pipeline '" .. self.filename .. "'" )
	end

	self.handle = util.open_uri_handle( max_weight_uri )
	self.uri = max_weight_uri

	for i = 1, #self.plugins do
		for mode in self.plugins[i].mode:gmatch "[^;,]+" do
			mode = mode:gsub( "^%s+", "" ):gsub( "%s+$", "" )

			if mode == "*" or mode == max_weight_mode then
				self:initialise_plugin( self.plugins[i] )
			end
		end
	end
end

return pipeline
