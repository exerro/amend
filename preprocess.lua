
local preprocess = {}

local commands = {}

local function unstringify( s )
	return assert( load( "return" .. s, "string value", nil, {} ) )()
end

local function normalise( path )
	return path
		  :gsub( "//+", "/" )
		  :gsub(  "^/",  "" )
		  :gsub(  "/$",  "" )
end

local function getcwd( str, path )
	local t = { path = path }
	local i = 1

	for seg in str:gmatch "[^/]+" do
		t[i] = seg
		i = i + 1
	end

	return t
end

local function splitat( dat, pat )
	local segments = {}
	local i = 1
	local p = 1
	local s, f = dat:find( pat )

	while s do
		segments[i] = dat:sub( p, s - 1 )
		p = f + 1
		s, f = dat:find( pat, f + 1 )
		i = i + 1
	end

	segments[i] = dat:sub( p )

	return segments
end

local function splitpaths( path )
	return path == "" and { "" } or splitat( path, ";" )
end

local function tolines( content, source )
	local lines = {}
	local i = 1
	local p = 1
	local s = content:find "\n"

	while s do
		lines[i] = { content = content:sub( p, s - 1 ), line = i, source = source }
		p = s + 1
		i = i + 1
		s = content:find( "\n", p )
	end

	lines[i] = { content = content:sub( p ), line = i, source = source, error = nil }

	return lines
end

local function find_non_escaped( line, pat, pos )
	local closer = line:find( pat, pos )
	local escape = line:find( "\\", pos )
	local patlen = #pat

	if not closer then
		return nil
	end

	while escape and escape < closer do
		if escape == closer - 1 then
			closer = line:find( pat, closer + patlen )
		end
		escape = line:find( "\\", escape + 2 )
	end

	return closer
end

local function splitspaced( str )
	local s, f = str:find "%S+"
	local segments = {}
	local i = 1

	while s do
		local seg = str:sub( s, f )
		local pos = seg:find "'" or seg:find '"'

		if pos then
			if pos > 1 then
				segments[i] = seg:sub( 1, pos - 1 )
				i = i + 1
			end

			s = s + pos - 1

			local ch = seg:sub( pos, pos )
			local close_pos = find_non_escaped( str, ch, s + 1 )

			if close_pos then
				segments[i] = str:sub( s, close_pos )
				s, f = str:find( "%S+", close_pos + 1 )
				i = i + 1
			else
				segments[i] = str:sub( s )
				return segments, ch
			end
		elseif str:find( "^%[=*%[", s ) then -- multiline string
			error "multiline strings are not yet supported"
		else
			segments[i] = seg
			i = i + 1
			s, f = str:find( "%S+", f + 1 )
		end
	end

	return segments, false
end

local function microminify( line, state )
	local n = 1
	local res = {}
	local is_word = false
	local first_segment

	if state.in_string then
		local pos = find_non_escaped( line, state.string_closer, 1 )

		if pos then
			first_segment = line:sub( 1, pos )
			line = line:sub( pos + 1 )
			state.in_string = false
		else
			first_segment = line
			line = ""
		end
	end

	local segments, strch = splitspaced( line )

	if first_segment then
		table.insert( segments, 1, first_segment )
	end

	if strch then
		state.in_string = true
		state.string_closer = strch
	end

	for i = 1, #segments do
		if is_word and segments[i]:find "^[%w_]" then
			res[n] = " "
			n = n + 1
		end
		res[n] = segments[i]
		n = n + 1
		is_word = segments[i]:find "[%w_]$"
	end

	return table.concat( res )
end

local function apply_function_macros( str, state )
	if not str then error( "here", 3 )end
	return str:gsub( "([%w_]+)(%b())", function( func, params )
		local lookup = {}

		if state.environment[func] and type( state.environment[func] ) == "table" and state.environment[func].type == "function" then
			params = params:sub( 2, -2 )
			local paramt = {}
			local segments = {}
			local i = 1
			local p = 1

			local s, f = params:find ","

			while s do
				local str = params:sub( p, s - 1 )
				if select( 2, str:gsub( "%(", "" ) ) == select( 2, str:gsub( "%)", "" ) ) then
					segments[i] = str:gsub( "^%s+", "" ):gsub( "%s+$", "" )
					p = f + 1
					i = i + 1
				end
				s, f = params:find( ",", f + 1 )
			end

			segments[i] = params:sub( p ):gsub( "^%s+", "" ):gsub( "%s+$", "" )

			for i = 1, #segments do
				paramt["__param" .. i] = segments[i]
			end

			return state.environment[func].body:gsub( "__param%d+", paramt )
		else
			func = func .. apply_function_macros( params, state )
		end

		return func
	end )
end

local function fmtline( line, state )
	if state.ifstack_resultant then
		-- apply macros
		line = apply_function_macros( line, state )

		line = line:gsub( "[%w_]+", function( word )
			local lookup = {}

			while state.environment[word] do
				lookup[word] = true
				word = tostring( state.environment[word] )

				if lookup[word] then
					break
				end
			end

			return word
		end )

		if state.microminify then
			line = microminify( line, state )
		else
			for i = 1, #state.ifstack do
				if line:sub( 1, 1 ) == "\t" then
					line = line:sub( 2 )
				else
					break
				end
			end
		end

		return line
	end

	return ""
end

local function fmtlineout( data, state )
	data = apply_function_macros( data, state )

	return (data:gsub( "$([%w_]+)", function( word )
		if state.environment[word] then
			local lookup = {}
			while state.environment[word] do
				lookup[word] = true
				word = tostring( state.environment[word] )

				if lookup[word] then
					break
				end
			end
		else
			word = "<undefined>"
		end
		return word
	end ))
end

local function resolvefile( file, state, raw )
	local cwd = state.cwd[#state.cwd] or {}
	local paths = splitpaths( tostring( state.environment.PATH ) )
	local filepath = raw and file or file:gsub( "%.", "/" )
	local filename = filepath:match ".+/(.*)" or filepath
	local tried_paths = {}

	if filepath:sub( 1, 1 ) == "/" or raw then
		paths = { "" }
	end

	for i = 1, #paths do
		for n = paths[i] == cwd.path and #cwd or 0, 0, -1 do
			local path = normalise( paths[i] .. "/" .. table.concat( cwd, "/", 1, n ) .. "/" .. filepath )
			local newcwd
			local h = io.open( path .. ".lua", "r" )

			if h then
				newcwd = getcwd( table.concat( cwd, "/", 1, n ) .. "/" .. filepath:sub( 1, -1 - #filename ), normalise( paths[i] ) )
			else
				tried_paths[#tried_paths + 1] = path
				path = path .. "/" .. filename
				h = io.open( path .. ".lua", "r" )

				if h then
					newcwd = getcwd( table.concat( cwd, "/", 1, n ) .. "/" .. filepath, normalise( paths[i] ) )
				end
			end

			tried_paths[#tried_paths + 1] = path

			if h then
				return h, path, newcwd
			end
		end
	end

	return nil, tried_paths
end

local function processline( lines, src, line, state )
	local linestr = lines[line].content
	local command, res = linestr:match "^%s*%-%-%s*@(%w+)%s*(.*)"
	local skip = 0

	if not command then
		command, res = linestr:match "^%s*@(%w+)%s*(.*)"
	end

	if command then
		lines[line].content = ""
		if commands[command] then
			skip = commands[command]( res, src, line, lines, state ) or 0
		else
		    error( "cannot execute instruction '" .. command .. "' on line " .. line .. " of '" .. src .. "'", 0 )
		end
	end

	lines[line].content = fmtline( lines[line].content, state )

	return skip
end

function preprocess.process_content( content, source, state )
	local lines = tolines( content, source )
	local line = 1

	while line <= #lines do
		line = line + processline( lines, source, line, state ) + 1
	end

	return lines
end

function preprocess.process_file( file, state, raw )
	local h, path, newcwd = resolvefile( file, state, raw )

	if h then
		if state.include_cache[path] then
			h:close()
			return {}
		end

		local content = h:read "*a"

		h:close()
		state.include_cache[path] = true
		state.cwd[#state.cwd + 1] = newcwd

		return preprocess.process_content( content, file, state )
	end

	return nil, path
end

function preprocess.create_state( path )
	return {
		localised = {};
		ifstack_resultant = true;
		ifstack = {};
		ifmatched = {};
		environment = { PATH = path };
		errors = {};
		error_data = {};
		microminify = false;
		minify = {
			active = false;
			next_string = false;
		};
		cwd = {};
		include_cache = {};
		is_private = false;
	}
end

commands["localise"] = function( data, src, line, lines, state )
	if data:find "^[%w_]+$" then
		state.localised[data] = not state.is_private
		state.is_private = false
	else
		return error( "invalid name to localise: '" .. data .. "' on line " .. line .. " of '" .. src .. "'", 0 )
	end
end

commands["class"] = function( data, src, line, lines, state )
	local classname = data:match "^[%w_]+"
	   or error( "expected class name after '@class' on line " .. line .. " of '" .. src .. "'", 0 )
	local len, extends
	local interfacelist = {}

	data, len = data:gsub( classname .. "%s+", "", 1 )

	if len > 0 and data:sub( 1, 7 ) == "extends" then
		data, len = data:gsub( "extends%s+", "", 1 )

		if len == 0 then
			return error( "expected space after 'extends' on line " .. line .. " of '" .. src .. "'", 0 )
		else
			extends = data:match "^[%w_]+"
			       or error( "expected super class name after 'extends' on line " .. line .. " of '" .. src .. "'", 0 )
			data, len = data:gsub( extends .. "%s+", "", 1 )
		end
	end

	if len > 0 and data:sub( 1, 10 ) == "implements" then
		data, len = data:gsub( "implements%s+", "", 1 )

		if len == 0 then
			return error( "expected space after 'implements' on line " .. line .. " of '" .. src .. "'", 0 )
		else
			repeat
				iname = data:match "^[%w_]+"
				     or error( "expected interface name after 'implements' on line " .. line .. " of '" .. src .. "'", 0 )

				interfacelist[#interfacelist + 1] = iname
				data = data:sub( #iname + 1 )
				data, len = data:gsub( "^,%s+", "", 1 )
			until len == 0
		end
	end

	if not data:find "^%s*{?%s*$" then
		return error( "unexpected '" .. data .. "' after class definition on line " .. line .. " of '" .. src .. "'", 0 )
	end

	lines[line].content = ("%s = class.new( %q, %s, %s ) {")
	           :format( classname, classname, extends or "nil", #interfacelist > 0 and table.concat( interfacelist, ", " ) or "nil" )

	state.localised[classname] = not state.is_private
	state.is_private = false
end

commands["interface"] = function( data, src, line, lines, state )
	local interfacename = data:match "^[%w_]+"
	   or error( "expected interface name after '@interface' on line " .. line .. " of '" .. src .. "'", 0 )
	local len
	local interfacelist = {}

	data, len = data:gsub( interfacename .. "%s+", "", 1 )

	if len > 0 and data:sub( 1, 10 ) == "implements" then
		data, len = data:gsub( "implements%s+", "", 1 )

		if len == 0 then
			return error( "expected space after 'implements' on line " .. line .. " of '" .. src .. "'", 0 )
		else
			repeat
				iname = data:match "^[%w_]+"
					 or error( "expected interface name after 'implements' on line " .. line .. " of '" .. src .. "'", 0 )

				interfacelist[#interfacelist + 1] = iname
				data = data:sub( #iname + 1 )
				data, len = data:gsub( "^,%s+", "", 1 )
			until len == 0
		end
	end

	if not data:find "^%s*{?%s*$" then
		return error( "unexpected '" .. data .. "' after interface definition on line " .. line .. " of '" .. src .. "'", 0 )
	end

	lines[line].content = ("%s = class.new_interface( %q, %s ) {")
			   :format( interfacename, interfacename, #interfacelist > 0 and table.concat( interfacelist, ", " ) or "nil" )

	state.localised[interfacename] = not state.is_private
	state.is_private = false
end

commands["enum"] = function( data, src, line, lines, state )
	if data:find "^[%w_]+ {$" then
		local name = data:sub( 1, -3 )
		state.localised[name] = not state.is_private
		state.is_private = false
		lines[line].content = ("%s = class.new_enum %q {"):format( name, name )
	else
		return error( "invalid name to localise: '" .. data .. "' on line " .. line .. " of '" .. src .. "'", 0 )
	end
end

commands["define"] = function( data, src, line, lines, state )
	local name = data:match "^[%w_%-]+"
	          or error( "expected name after @define (got '" .. data .. "') on line " .. line .. " of '" .. src .. "'", 0 )

	data = data:sub( #name + 1 )

	local funcargs = data:match "^%s*%((.-)%)"

	if funcargs then
		data = data:match "^%s*%(.-%)(.*)"
	end

	local value = data:match( "%s+(.*)" ) or "true"

	if funcargs then
		local args = splitat( funcargs, ",%s*" )
		local lookup = {}

		for i = 1, #args do
			lookup[args[i]] = "__param" .. i
			args[i] = "__param" .. i
		end

		value = value:gsub( "%w+", function( s )
			return lookup[s] or s
		end )

		value = { type = "function", args = args, body = value }
	elseif value == "true" or value == "false" then
		value = value == "true"
	elseif tonumber( value ) then
		value = tonumber( value )
	end

	state.environment[name] = value
end

commands["defineifndef"] = function( data, src, line, lines, state )
	local name = data:match "^[%w_%-]+"
	          or error( "expected name after @defineifndef (got '" .. data .. "') on line " .. line .. " of '" .. src .. "'", 0 )

	if not state.environment[name] then
		data = data:sub( #name + 1 )

		local funcargs = data:match "^%s*%((.-)%)"

		if funcargs then
			data = data:match "^%s*%(.-%)(.*)"
		end

		local value = data:match( "%s+(.*)" ) or "true"

		if funcargs then
			local args = splitat( funcargs, ",%s*" )
			local lookup = {}

			for i = 1, #args do
				lookup[args[i]] = "__param" .. i
				args[i] = "__param" .. i
			end

			value = value:gsub( "%w+", function( s )
				return lookup[s] or s
			end )

			value = { type = "function", args = args, body = value }
		elseif value == "true" or value == "false" then
			value = value == "true"
		elseif tonumber( value ) then
			value = tonumber( value )
		end

		state.environment[name] = value
	end
end

commands["unset"] = function( data, src, line, lines, state )
	local name = data:match "^[%w_%-]+$"
			  or error( "expected name after @unset (got '" .. data .. "') on line " .. line .. " of '" .. src .. "'", 0 )

	state.environment[name] = nil
end

commands["print"] = function( data, src, line, lines, state )
	if state.ifstack_resultant then
		return print( fmtlineout( data, state ) )
	end
end

commands["error"] = function( data, src, line, lines, state )
	if state.ifstack_resultant then
		return error( fmtlineout( data, state ), 0 )
	end
end

commands["if"] = function( data, src, line, lines, state )
	local name = data:match "^[%w_%-]+$"
			  or error( "expected name after @if (got '" .. data .. "') on line " .. line .. " of '" .. src .. "'", 0 )
	local env = state.environment[name]
	local condition = not not env

	if type( env ) == "number" then
		condition = env > 0
	elseif type( env ) == "string" then
		condition = #env > 0
	end

	state.ifstack[#state.ifstack + 1] = state.ifstack_resultant and condition
	state.ifstack_resultant = state.ifstack[#state.ifstack]
	state.ifmatched[#state.ifstack] = condition
end

commands["ifn"] = function( data, src, line, lines, state )
	local name = data:match "^[%w_%-]+$"
			  or error( "expected name after @ifn (got '" .. data .. "') on line " .. line .. " of '" .. src .. "'", 0 )
	local env = state.environment[name]
	local condition = not env

	if type( env ) == "number" then
		condition = env == 0
	elseif type( env ) == "string" then
		condition = #env == 0
	end

	state.ifstack[#state.ifstack + 1] = state.ifstack_resultant and condition
	state.ifstack_resultant = state.ifstack[#state.ifstack]
	state.ifmatched[#state.ifstack] = condition
end

commands["ifdef"] = function( data, src, line, lines, state )
	local name = data:match "^[%w_%-]+$"
			  or error( "expected name after @ifdef (got '" .. data .. "') on line " .. line .. " of '" .. src .. "'", 0 )
	local env = state.environment[name]

	state.ifstack[#state.ifstack + 1] = state.ifstack_resultant and env ~= nil
	state.ifstack_resultant = state.ifstack[#state.ifstack]
	state.ifmatched[#state.ifstack] = env ~= nil
end

commands["ifndef"] = function( data, src, line, lines, state )
	local name = data:match "^[%w_%-]+$"
			  or error( "expected name after @ifndef (got '" .. data .. "') on line " .. line .. " of '" .. src .. "'", 0 )
	local env = state.environment[name]

	state.ifstack[#state.ifstack + 1] = state.ifstack_resultant and env == nil
	state.ifstack_resultant = state.ifstack[#state.ifstack]
	state.ifmatched[#state.ifstack] = env == nil
end

commands["elif"] = function( data, src, line, lines, state )
	local name = data:match "^[%w_%-]+$"
			  or error( "expected name after @elif (got '" .. data .. "') on line " .. line .. " of '" .. src .. "'", 0 )
	local env = state.environment[name]
	local condition = not not env

	if type( env ) == "number" then
		condition = env > 0
	elseif type( env ) == "string" then
		condition = #env > 0
	end

	if condition and not state.ifmatched[#state.ifstack] then
		state.ifstack_resultant = #state.ifstack == 1 and true or state.ifstack[#state.ifstack - 1]
		state.ifstack[#state.ifstack] = state.ifstack_resultant
		state.ifmatched[#state.ifstack] = true
	else
		state.ifstack_resultant = false
		state.ifstack[#state.ifstack] = false
	end
end

commands["elifn"] = function( data, src, line, lines, state )
	local name = data:match "^[%w_%-]+$"
			  or error( "expected name after @elifn (got '" .. data .. "') on line " .. line .. " of '" .. src .. "'", 0 )
	local env = state.environment[name]
	local condition = not env

	if type( env ) == "number" then
		condition = env == 0
	elseif type( env ) == "string" then
		condition = #env == 0
	end

	if condition and not state.ifmatched[#state.ifstack] then
		state.ifstack_resultant = #state.ifstack == 1 and true or state.ifstack[#state.ifstack - 1]
		state.ifstack[#state.ifstack] = state.ifstack_resultant
		state.ifmatched[#state.ifstack] = true
	else
		state.ifstack_resultant = false
		state.ifstack[#state.ifstack] = false
	end
end

commands["elifdef"] = function( data, src, line, lines, state )
	local name = data:match "^[%w_%-]+$"
			  or error( "expected name after @elifdef (got '" .. data .. "') on line " .. line .. " of '" .. src .. "'", 0 )
	local env = state.environment[name]
	local condition = env ~= nil

	if condition and not state.ifmatched[#state.ifstack] then
		state.ifstack_resultant = #state.ifstack == 1 and true or state.ifstack[#state.ifstack - 1]
		state.ifstack[#state.ifstack] = state.ifstack_resultant
		state.ifmatched[#state.ifstack] = true
	else
		state.ifstack_resultant = false
		state.ifstack[#state.ifstack] = false
	end
end

commands["elifndef"] = function( data, src, line, lines, state )
	local name = data:match "^[%w_%-]+$"
			  or error( "expected name after @elifndef (got '" .. data .. "') on line " .. line .. " of '" .. src .. "'", 0 )
	local env = state.environment[name]
	local condition = env == nil

	if condition and not state.ifmatched[#state.ifstack] then
		state.ifstack_resultant = #state.ifstack == 1 and true or state.ifstack[#state.ifstack - 1]
		state.ifstack[#state.ifstack] = state.ifstack_resultant
		state.ifmatched[#state.ifstack] = true
	else
		state.ifstack_resultant = false
		state.ifstack[#state.ifstack] = false
	end
end

commands["else"] = function( data, src, line, lines, state )
	if data ~= "" then
		return error( "unexpected data after @else ('" .. data .. "') on line " .. line .. " of '" .. src .. "'", 0 )
	end

	if not state.ifmatched[#state.ifstack] then
		state.ifstack_resultant = #state.ifstack == 1 and true or state.ifstack[#state.ifstack - 1]
		state.ifstack[#state.ifstack] = state.ifstack_resultant
		state.ifmatched[#state.ifstack] = true
	else
		state.ifstack_resultant = false
		state.ifstack[#state.ifstack] = false
	end
end

commands["endif"] = function( data, src, line, lines, state )
	if data ~= "" then
		return error( "unexpected data after @endif ('" .. data .. "') on line " .. line .. " of '" .. src .. "'", 0 )
	end

	if #state.ifstack > 0 then
		state.ifstack[#state.ifstack] = nil
		state.ifmatched[#state.ifmatched] = nil

		if #state.ifstack == 0 then
			state.ifstack_resultant = true
		else
			state.ifstack_resultant = state.ifstack[#state.ifstack]
		end
	else
		return error( "no if block to end on line " .. line .. " of '" .. src .. "'", 0 )
	end
end

commands["include"] = function( data, src, line, lines, state )
	local file = data:match "^[%w_%.]+$"
	          or error( "expected valid name after @include, got '" .. data .. "' on line " .. line .. " of '" .. src .. "'", 0 )
	if state.ifstack_resultant then
		local sublines = preprocess.process_file( file, state )
			or error( "failed to find file '" .. file .. "' on line " .. line .. " of '" .. src .. "'", 0 )
		local len = #sublines

		for i = #lines, line + 1, -1 do
			lines[i + len] = lines[i]
		end

		for i = 1, len do
			lines[line + i] = sublines[i]
		end

		return len
	end
end

commands["includeraw"] = function( data, src, line, lines, state )
	local file = data:match "^[%w_%./]+$"
	          or error( "expected valid name after @includeraw, got '" .. data .. "' on line " .. line .. " of '" .. src .. "'", 0 )
	if state.ifstack_resultant then
		local sublines = preprocess.process_file( file, state, true )
			or error( "failed to find file '" .. file .. "' on line " .. line .. " of '" .. src .. "'", 0 )
		local len = #sublines

		for i = #lines, line + 1, -1 do
			lines[i + len] = lines[i]
		end

		for i = 1, len do
			lines[line + i] = sublines[i]
		end

		return len
	end
end

commands["import"] = function( data, src, line, lines, state )
	local file, name = data:match "^([%w_%./]+)%s+as%s+([%w_]+)$"

	if not file then
		file = data:match "^[%w_%./]+/[%w_]+$" or data:match "^[%w_]+$" or data:match "^[%w_%./]+/[%w_]+%.pack$" or data:match "^[%w_]+%.pack$"
		       or error( "expected <path> [as <name>] after @import, got '" .. data .. "' on line " .. line .. " of '" .. src .. "'", 0 )
		name = (file:match ".+/(.*)$" or file):gsub( "%.pack$", "", 1 )
	end

	if state.ifstack_resultant then
		local name_env_add = name:upper() .. "_"
		local name_err_add = name:lower() .. "_"
		local localised_names = {}
		local localised = {}
		local exports = {}
		local environment, error_data, localised, sublines

		if file:sub( -5 ) == ".pack" then
			local h, path = resolvefile( file, state, true )

			if h then
				local content = h:read "*a"

				h:close()

				local f = assert( load( content, file:match ".+/(.*)" or file, nil, {} ) )

				environment, error_data, localised, sublines = f()
			else
				error( "failed to find file '" .. file .. "' on line " .. line .. " of '" .. src .. "'", 0 )
			end
		else
			local substate = preprocess.create_state( file:match "(.+)/" or "" )
			local name_env_pat = "^" .. name:upper() .. "_"
			local name_env_len = #name_env_pat

			substate.microminify = state.microminify
			substate.minify.active = state.minify.active

			for k, v in pairs( state.environment ) do
				if k:find( name_env_pat ) then
					substate.environment[k:sub( name_env_len )] = v
				end
			end

			sublines = preprocess.process_file( file, substate, true )
				or error( "failed to find file '" .. file .. "' on line " .. line .. " of '" .. src .. "'", 0 )

			environment = substate.environment
			error_data = substate.error_data
			localised = substate.localised
		end

		for k, v in pairs( environment ) do
			state.environment[name_env_add .. k] = v
		end

		for k, v in pairs( error_data ) do
			state.error_data[name_err_add .. k] = v
		end

		for k, v in pairs( localised ) do
			if v then
				exports[#exports + 1] = name .. "." .. k .. " = " .. k
			end
			localised_names[#localised_names + 1] = k
		end

		local len = #sublines + 1

		state.localised[name] = not state.is_private
		state.is_private = false
		lines[line].content = "do " .. name .. " = {}" .. (#localised_names > 0 and " local " .. table.concat( localised_names, ", " ) or "")
		sublines[len] = { content = table.concat( exports, "; " ) .. " end", source = "<preprocessor>", line = 0 }

		for i = #lines, line + 1, -1 do
			lines[i + len] = lines[i]
		end

		for i = 1, len do
			lines[line + i] = sublines[i]
			if sublines[i].error then
				sublines[i].error[1] = name_err_add .. sublines[i].error[1]
			end
		end

		return len
	end
end

commands["minifystr"] = function( data, src, line, lines, state )
	if data ~= "" then
		return error( "unexpected data after @minifystr ('" .. data .. "') on line " .. line .. " of '" .. src .. "'", 0 )
	end

	if state.minify.active then
		state.minify.next_string = true
	end
end

commands["throws"] = function( data, src, line, lines, state )
	local name, args = data:match "^([%w_%.%-]+)%s*(.*)$"

	if not name then
		error( "expected valid name after @throws, got '" .. data .. "' on line " .. line .. " of '" .. src .. "'", 0 )
	end

	if state.error_data[name] then
		if lines[line + 1] then
			lines[line + 1].error = { name, unpack( splitspaced( args ), 1 ) }
		else
			error( "expected line after @throws on line " .. line .. " of '" .. src .. "'", 0 )
		end
	else
		return error( "undefined error name after @throws ('" .. name .. "') on line " .. line .. " of '" .. src .. "'", 0 )
	end
end

commands["errordata"] = function( data, src, line, lines, state )
	local name = data:match "^([%w_%.%-]+)%s"
	          or error( "expected valid name after @errordata, got '" .. data .. "' on line " .. line .. " of '" .. src .. "'" )

	data = data:gsub( name:gsub( "%.", "%%%." ) .. "%s+", "", 1 )

	if data:sub( 1, 1 ) == "'" or data:sub( 1, 1 ) == '"' then
		local pat = data:sub( 1, find_non_escaped( data, data:sub( 1, 1 ), 2 )
		                      or error( "expected closing '" .. data:sub( 1, 1 ) .. "' for errordata pattern on line " .. line .. " of '" .. src .. "'", 0 ) )

		data = data:sub( #pat + 1 ):match "^%s+(.*)"
		    or error( "expected data after errordata pattern on line " .. line .. " of '" .. src .. "'", 0 )

		state.error_data[name] = state.error_data[name] or {}
		state.error_data[name][#state.error_data[name] + 1] = { unstringify( pat ), data }
	elseif data:sub( 1, 9 ) == "extension" then
		local subname = name:match "(.+)%."
		             or error( "expected '<parent>.' (got '" .. name .. "') on line " .. line .. " of '" .. src .. "'", 0 )

		if not state.error_data[subname] then
			return error( "invalid errordata extension parent ('" .. subname .. "') on line " .. line .. " of '" .. src .. "'", 0 )
		end

	  	state.error_data[name] = state.error_data[name] or {}

		data = data:match "^extension%s+(.*)"
		    or error( "expected data after 'extension' on line " .. line .. " of '" .. src .. "'", 0 )

		for i = 1, #state.error_data[subname] do
			state.error_data[name][#state.error_data[name] + 1] = { state.error_data[subname][i][1], state.error_data[subname][i][2] .. ": " .. data }
		end
	end
end

commands["private"] = function( data, src, line, lines, state )
	if data:find "%S" then
		error( "unexpected data after @private on line " .. line .. " of '" .. src .. "'", 0 )
	end

	state.is_private = true
end

return preprocess
