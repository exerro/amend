
local warning = require "warning"
local ID = 0
local pipeline = {}

function pipeline:new( filename, plugins )
	ID = ID + 1
	local p = setmetatable( {
		ID = ID,
		filename = filename,
		plugins = plugins,
		meta = {},
		handle = nil,
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

	return p
end

function pipeline:initialise_plugin( plugin )
	self.meta[plugin.name] = plugin.state( self )
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
	local file_list = {}
	local max_weight = 0
	local max_weight_handle = nil
	local max_weight_mode = nil
	local handles_to_close = {}

	for i = 1, #self.plugins do
		local callbacks = self.plugins[i].file_lookup_callbacks
		for j = 1, #callbacks do
			local t = callbacks[j]( self )

			for i = 1, #t do
				local handle, weight, mode = t[i][1], t[i][2], t[i][3]

				if weight > max_weight then
					handles_to_close[#handles_to_close + 1] = max_weight_handle
					max_weight = weight
					max_weight_handle = handle
					max_weight_mode = mode
				else
					handles_to_close[#handles_to_close + 1] = handle
				end
			end
		end
	end

	for i = 1, #handles_to_close do
		handles_to_close[i]:close()
	end

	if not max_weight_handle then
		return warning.error( warning.PIPELINE_HANDLE_ERR, "failed to get handle for pipeline '" .. self.filename .. "'" )
	end

	self.handle = max_weight_handle

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
