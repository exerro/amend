
local util = {}

function util.parse_args( args )
	local options = {}
	local feeding = nil

	while args[1] do
		local arg = args[1]

		if arg:sub( 1, 1 ) == "-" then
			local long_name = arg:sub( 2, 2 ) == "-"
			local name = long_name and (arg:match "^%-%-([^=]+)" or "") or arg:sub( 2, 2 )
			local value = arg:sub( (long_name and 2 or 1) + #name + 1 ):sub( 1, 1 ) == "=" and arg:sub( (long_name and 2 or 1) + #name + 2 )
			local default = not value and long_name and {} or "true"

			table.remove( args, 1 )

			if long_name and not value then
				feeding = default
			else
				feeding = nil
			end

			if name == "" then
				break
			else
				options[name] = value or default
			end
		elseif feeding then
			feeding[#feeding + 1] = arg
			table.remove( args, 1 )
		else
			break
		end
	end

	return options, args
end

function util.open_uri_handle( uri )
	local protocol, data = uri:match "^([%w_%-]+)://(.*)"

	protocol = protocol or "file"
	data = data or uri

	if protocol == "file" then
		return io.open( data, "r" )
	else
		return error( "protocol '" .. protocol .. "' is not supported", 0 )
	end
end

function util.has_uri_protocol( str )
	return str:find( "^[%w_%-]+://" ) and true or false
end

function util.format_string( str, env, ... )
	if type( env ) ~= "table" then
		env = { env, ... }
	end
	return str:gsub( "$([%w_]+)", function( s )
		return env[s:find( "^%d+$" ) and tonumber( s ) or s]
	end )
end

return util
