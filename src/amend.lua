
if not require then
	local dofile = dofile

	if not dofile then
		function dofile( file, ... )
			if type( file ) ~= "string" then
				return error( "expected string file, got " .. type( file ) )
			end
			local f, err = loadfile( file, file:gsub( ".+/", "" ) )
			if f then
				local data = { pcall( f, ... ) }
				if data[1] then
					return unpack( data, 2 )
				else
					err = data[2]
				end
			end
			return error( err, 0 )
		end
	end

	local cache = {}

	function require( filename )
		if not cache[filename] then
			cache[filename] = dofile( filename ) or true
		end
		return cache[filename]
	end
end

local util = require "util"
local build = require "build"

local options, args = util.parse_args { ... }
local thisbuild = build:new( table.concat( options.path or {}, ";" ) .. ";/amend/plugins" )

thisbuild:plugin( "print.lua" )

for i = 1, #args do
	thisbuild:include( args[i] )
end
