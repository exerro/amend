
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

return util
