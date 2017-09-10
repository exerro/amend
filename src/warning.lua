
local warning = {}

local WIGNORE = 0
local WWARN = 1
local WERROR = 2

warning.PLUGIN_ERR = "PLUGIN_ERROR"
warning.PIPELINE_HANDLE_ERR = "PIPELINE_HANDLE_ERROR"
warning.CONFLICTING_LOOKUP = "CONFLICTING_LOOKUP"
warning.URI_HANDLE_OPEN_FAIL = "URI_HANDLE_OPEN_FAILURE"
warning.PROTOCOL_UNMATCHED = "PROTOCOL_UNMATCHED"

warning.statuses = setmetatable( {}, { __index = function() return WWARN end } )

function warning.error( wcode, message )
	return error( tostring( wcode ) .. ": " .. message, 0 )
end

function warning.warn( wcode, message )
	local status = warning.statuses[wcode]

	if status == WERROR then
		return error( wcode .. ": " .. message, 0 )
	elseif status == WWARN then
		return print( wcode .. ": " .. message )
	end
end

function warning.info( info )
	return print( info )
end

function warning.status( wcode, status )
	if status then
		warning.statuses[wcode] = status
	end
	return warning.statuses[wcode]
end

return warning
