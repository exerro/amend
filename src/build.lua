
local pipeline = require "pipeline"
local plugin = require "plugin"
local stream = require "stream"

local build = {}

function build:new()
	local paths = {}
	local b = setmetatable( {
		environment = {},
		options = options,
		paths = paths,
		plugins = {},
	}, { __index = self } )

	return b
end

function build:plugin( plugin_name )
	for i = 1, #self.plugins do
		if self.plugins[i].name == plugin_name then
			return
		end
	end

	local p = plugin.load( plugin_name, self.paths )

	if p then
		self.plugins[#self.plugins + 1] = p
		p:load( self )
	end
end

function build:include( file, host )
	print "nopety nope nope"
end

-- stop making eucky looking doc comments all over the place
function build:get_URI_list( filename )
	local URIs = {}
	local n = 0
	local max_weight = -1

	for i = 1, #self.plugins do
		local callbacks = self.plugins[i].file_lookup_callbacks
		for j = 1, #callbacks do
			local t = callbacks[j]( filename, self )
			local weight = 0 -- TODO

			if #t > 0 and weight > max_weight then
				max_weight = weight
				URIs = t
			end
		end
	end

	return URIs
end

return build
