
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

function build:new( path )
	local b = setmetatable( {
		paths = split_path( path ),
		plugins = {},
	}, { __index = self } )

	return b
end

function build:plugin( plugin_name )
	self.plugins[#self.plugins + 1] = plugin.load( plugin_name, self.paths )
end

function build:include( file )
	local p = pipeline:new( file, copy( self.plugins ) )

	p:get_handle()
	-- ...
end
