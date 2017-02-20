
local args = { ... }
local HELP = [[
Usage
 > amend.lua <files...> [-options]
 > amend.lua -h|help|--help
 --> display help

Options
 --flag; -f <flag>
    set <flag> to 'true' in the file env
 --output; -o <path>
    add an output path
 --source; -s <path>
    add an include path
 --mode; -m <mode>
    set compilation mode

Valid compilation modes are 'executable' ('-me') and 'package' ('mp')
Input paths are relative and use dot notation (subdir.file not subdir/file.lua)
Sources and outputs are absolute with no extension]]

local DEBUG_TRACKER_FUNCTION = [[
local function __get_src_and_line( line )
	for i = 1, #__debug_line_tracker do
		local t = __debug_line_tracker[i]
		if line >= t[1] and line <= t[2] then
			return t[3], t[4] + line - t[1]
		end
	end
	return "unknown source", 0
end]]

local ERR_MAPPING_FUNCTION = [[
local function __get_err_msg( src, line, err )
	if __debug_err_map[src] and __debug_err_map[src][line] then
		local name = __debug_err_map[src][line][1]
		for i = 1, #__debug_err_pats[name] do
			local data, r = err:gsub( __debug_err_pats[name][i][1], __debug_err_pats[name][i][2]:gsub( "%$%{(%d+)%}", function( n )
				return __debug_err_map[src][line][tonumber( n ) + 1]
			end ), 1 )
			if r > 0 then
				return data
			end
		end
	end
	return err
end]]

local DEBUG_PCALL = [[
local __debug_ok, __debug_err = pcall( function()
LINES
end )
if not __debug_ok then
	if type( __debug_err ) == "string" then
		local e = select( 2, pcall( error, "@", 2 ) )
		local src = e:match "^(.*):%d+: @$"
		local line, msg = __debug_err:match( src .. ":(%d+): (.*)" )

		if line then
			local src, line = __get_src_and_line( tonumber( line ) )
			return error( src .. "[" .. line .. "]: " .. __get_err_msg( src, line, msg ), 0 )
		end
	end

	return error( __debug_err, 0 )
end]]

if args[1] == "-h" or args[1] == "help" or args[1] == "--help" then
	print( HELP )
	return
end

local inputs = {}
local flags = {}
local outputs = {}
local sources = {}
local modes = {}

local flag_modifier
local preprocess = dofile "amend/preprocess.lua"

local function countlines( str )
	return select( 2, str:gsub( "\n", "" ) ) + 1
end

for i = 1, #args do
	if flag_modifier then
		if flag_modifier == "flag" then
			flags[#flags + 1] = args[i]
		elseif flag_modifier == "output" then
			outputs[#outputs + 1] = args[i]
		elseif flag_modifier == "source" then
			sources[#sources + 1] = args[i]
		elseif flag_modifier == "mode" then
			if args[i] == "executable" or args[i] == "package" then
				modes[args[i]] = true
			else
				error( "invalid compilation mode '" .. args[i] .. "'", 0 )
			end
		end

		flag_modifier = nil
	elseif args[i] == "--flag" or args[i] == "-f" then
		flag_modifier = "flag"
	elseif args[i] == "--output" or args[i] == "-o" then
		flag_modifier = "output"
	elseif args[i] == "--source" or args[i] == "-s" then
		flag_modifier = "source"
	elseif args[i] == "--mode" or args[i] == "-m" then
		flag_modifier = "mode"
	elseif args[i] == "-me" then
		modes.executable = true
	elseif args[i] == "-mp" then
		modes.package = true
	else
		inputs[#inputs + 1] = args[i]
	end
end

if flag_modifier then
	error( "expected parameter after --" .. flag_modifier, 0 )
end

if not next( modes ) then
	modes.executable = true
end

if #inputs == 0 then
	error( "expected 1 or more input files", 0 )
end

if #outputs == 0 then
	local dir = (sources[1] and sources[1] .. "/" or "") .. (inputs[1]:match "(.+%." or ""):gsub( "%.", "/" )
	local name = "out/" .. (inputs[1]:match ".+%.(.*)" or inputs[1])
	outputs[1] = dir .. name
end

local state = preprocess.create_state( table.concat( sources, ";" ) )
local lines = {}
local linec = 0
local executable_compiled
local package_compiled

for i = 1, #flags do
	state.environment[flags[i]] = true
end

for i = 1, #inputs do
	local file_lines, paths_tried = preprocess.process_file( inputs[i], state )
	local file_linec = file_lines and #file_lines

	if not file_lines then
		error( "failed to read input '" .. inputs[i] .. "', tried paths:\n    " .. table.concat( paths_tried, "\n    " ), 0 )
	end

	for n = 1, file_linec do
		lines[linec + n] = file_lines[n]
	end

	linec = linec + file_linec
end

local local_list = {} -- string[] list of local names
local i = 0 -- tracks index in local_list
local n = 0 -- tracks the number of line mapping blocks
local l = 1 -- tracks the current relative line in the compiled output
local line_tracker = {} -- stores line mappings
local lines_compiled = {} -- stores compiled source lines
local errors = {} -- string[]{string} stores error mappings
local errors_raw = {} -- temporary for calculating errors table
local error_data = {} -- string[] stores error data
local elength = 0 -- internal length of error mapping table
local offset = 0 -- header line count

-- section one: local list
for k, v in pairs( state.localised ) do
	i = i + 1
	local_list[i] = k
end

offset = offset + (i == 0 and 0 or 1) -- 1 line if any locals defined, 0 otherwise

-- section two: error name mapping
for k, v in pairs( state.errors ) do
	for n = 1, #v do
		local t = { ("%q"):format( k ) }

		for i = 1, #v[n][3] do
			t[i + 1] = ("%q"):format( v[n][3][i] )
		end

		errors_raw[v[n][1]] = errors_raw[v[n][1]] or {}
		errors_raw[v[n][1]][#errors_raw[v[n][1]] + 1] = "[" .. v[n][2] .. "]={" .. table.concat( t, "," ) .. "}"
	end
end

for k, v in pairs( errors_raw ) do
	local s = table.concat( v, ";\n" )

	errors[#errors + 1] = ("[%q]={\n\t\t%s\n\t}"):format( k, table.concat( v, ";\n\t\t" ) )
	elength = elength + #v + 2
end

if #errors > 0 then
	offset = offset + 2 + elength -- 2 for opening and closing bracket lines, elength for internal size
end

-- section three: error data store
for k, v in pairs( state.error_data ) do
	local t = {}
	local pats = {}

	for i = 1, #v do
		t[i] = ("{%s,%q}"):format( v[i][1], v[i][2] )
	end

	error_data[#error_data + 1] = ("[%q]={%s}"):format( k, table.concat( t, "," ) )
end

if #errors == 0 then
	error_data = {}
end

if #errors > 0 then
	offset = offset + 2 + #error_data -- 2 for opening and closing brackets, #error_data for number of error data lines
end

-- section four: line mapping table
-- deferred

-- section five: constant function strings
offset = offset + countlines( DEBUG_TRACKER_FUNCTION ) -- debug tracker

if #errors > 0 then
	offset = offset + countlines( ERR_MAPPING_FUNCTION )
end

-- section six: opening pcall string
offset = offset + 1

-- section seven: compiled output
for i = 1, #lines do
	local space = not lines[i].content:find "%S" and false
	local same_tracker = line_tracker[n] and lines[i].source == line_tracker[n][3] and lines[i].line == line_tracker[n][5] + 1

	if lines[i].source ~= "<preprocessor>" then
		if same_tracker and not space then
			line_tracker[n][2] = l
			line_tracker[n][5] = lines[i].line
		elseif not same_tracker and not space then
			n = n + 1
			line_tracker[n] = { l, l, lines[i].source, lines[i].line, lines[i].line }
		end
	end

	if not space then
		lines_compiled[l] = lines[i].content
		l = l + 1
	end
end

-- section four offset
offset = offset + 2 + n -- 2 for opening and closing brackets, n for number of line mapping blocks

-- section eight: closing pcall string
-- empty section

-- conversion from line_tracker table to string
for i = 1, #line_tracker do
	line_tracker[i][1] = line_tracker[i][1] + offset
	line_tracker[i][2] = line_tracker[i][2] + offset
	line_tracker[i][3] = ("%q"):format( line_tracker[i][3] )
	line_tracker[i] = "{" .. table.concat( line_tracker[i], ",", 1, 4 ) .. "}"
end

if modes.executable then
	executable_compiled = table.concat {
		#local_list > 0 and "local " .. table.concat( local_list, "," ) .. "\n" or "";
		(#errors > 0 and "local __debug_err_map={\n\t" .. table.concat( errors, ";\n\t" ) .. "\n}\n" or "");
		(#errors > 0 and "local __debug_err_pats={\n\t" .. table.concat( error_data, ";\n\t" ) .. "\n}\n" or "");
		"local __debug_line_tracker={\n\t";
		table.concat( line_tracker, ",\n\t" );
		"\n}\n";
		DEBUG_TRACKER_FUNCTION .. "\n";
		(#errors > 0 and ERR_MAPPING_FUNCTION .. "\n" or "");
		(DEBUG_PCALL:gsub( "LINES", table.concat( lines_compiled, "\n" ), 1 ));
	}

	for i = 1, #outputs do
		local h = io.open( outputs[i] .. ".lua", "w" )

		if h then
			h:write( executable_compiled )
			h:close()
		else
			error( "failed to write to output '" .. outputs[i] .. "'", 0 )
		end
	end
end

if modes.package then
	error "Package mode is not currently implemented"

	-- this all needs to change...
	package_compiled = table.concat {
		#local_list > 0 and "local " .. table.concat( local_list, "," ) .. "\n" or "";
		(#errors > 0 and "local __debug_err_map={\n\t" .. table.concat( errors, ";\n\t" ) .. "\n}\n" or "");
		(#errors > 0 and "local __debug_err_pats={\n\t" .. table.concat( error_data, ";\n\t" ) .. "\n}\n" or "");
		"local __debug_line_tracker={\n\t";
		table.concat( line_tracker, ",\n\t" );
		"\n}\n";
		DEBUG_TRACKER_FUNCTION .. "\n";
		(#errors > 0 and ERR_MAPPING_FUNCTION .. "\n" or "");
		(DEBUG_PCALL:gsub( "LINES", table.concat( lines_compiled, "\n" ), 1 ));
	}

	for i = 1, #outputs do
		local h = io.open( outputs[i] .. ".pack.lua", "w" )

		if h then
			h:write( package_compiled )
			h:close()
		else
			error( "failed to write to output '" .. outputs[i] .. "'", 0 )
		end
	end
end
