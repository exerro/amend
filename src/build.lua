
local pipeline = require "pipeline"
local plugin = require "plugin"

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

return build
