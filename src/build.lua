
local pipeline = require "pipeline"
local plugin = require "plugin"
local stream = require "stream"

local build = {}

local function split_path( path )
	local paths, i = {}, 1

	for p in path:gmatch "[^;]+" do
		paths[i] = p
		i = i + 1
	end

	return paths
end

local function copy( t )
	local r = {}

	for i = 1, #t do
		r[i] = t[i]
	end

	return r
end

function build:new( options )
	local paths = {}

	for i = 1, #(options.path or {}) do
		paths[i] = options.path[i]
	end
	for i = 1, #(options.p or {}) do
		paths[#paths + 1] = options.p[i]
	end

	options.path = nil
	options.p = nil

	local b = setmetatable( {
		options = options,
		paths = paths,
		plugins = {},
	}, { __index = self } )

	return b
end

function build:plugin( plugin_name )
	local p = plugin.load( plugin_name, self.paths )

	self.plugins[#self.plugins + 1] = p
	p:load( self )
end

function build:include( file, host )
	local p = pipeline:new( file, copy( self.plugins ), host )

	p:get_handle()
	-- ...
end

--- Trigger file lookup.
-- @param filename	The filename to look for, passed to plugins' file lookup callback
-- @return An array of URIs
function build:get_URI_list( filename )
	local URIs = {}
	local n = 0

	for i = 1, #self.plugins do
		local callbacks = self.plugins[i].file_lookup_callbacks
		for j = 1, #callbacks do
			local t = callbacks[j]( self, filename )

			for k = 1, #t do
				n = n + 1
				URIs[n] = {
					path   = t[k][1];
					weight = t[k][2];
					mode   = t[k][3];
				}
			end
		end
	end

	return URIs
end

--- Get a new stream into URI.
-- @param URI	description
-- @return The stream object
function build:get_stream( URI )
	return stream.filestream:new( URI )
end

return build
