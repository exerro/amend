
local remove = table.remove
local find = string.find

--- Get a list of files inside a directory.
local function ls( path )
	if fs then
		local results = fs.list( path )
		return results, #results
	end

	local n = 0
	local results = {}

	if lfs then
		for name in lfs.dir( path ) do
			n = n + 1
			results[ n ] = name
		end

		return results, n
	end

	local f = io.popen( "ls -1 -a --color=none " .. path, "r" )

	if not f then
		error( "No provider for directory listings found", 2 )
	end

	local contents = f:read( "*a" )
	f:close()

	string.gsub( contents, "([^\n]*)\n", function( name )
		n = n + 1
		results[ n ] = name
	end )

	return results, n
end

--- Tries to determine whether `path` is an existing file.
-- @param path	The file to check
-- @return A boolean indicating the test result
local function is_file( path )
	if fs then
		return fs.exists( path ) and not fs.isDir( path )

	elseif lfs then
		local cwd = lfs.currentdir()
		local res = lfs.chdir( path )

		if res then
			lfs.chdir( cwd )
		end

		return lfs.attributes( path, "ino" ) and not res or false
	end

	local cmd = "[ -f " .. path .. " ]"

	if _VERSION == "Lua 5.1" then
		return os.execute( cmd ) == 0
	else
		return os.execute( cmd ) or false
	end
end

--- Convert a wildcard to a Lua pattern.
-- @param w	The wildcard to convert
-- @return The resultant pattern
local function wildcard_to_pattern( w )
	return "^" .. w:gsub( "([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1" ):gsub( "%%([%*%?])", ".%1" ) .. "$"
end

--- Find files by a module search path.
-- @param str	The module search path, a normal path with wildcards, Lua patterns (embedded in `backticks`),
--           	and implicit file extension completion
-- @return An array of the module's files, followed by its length
local function find_files( str )
	local paths_to_examine = { str }
	local n = 1

	local results = {}
	local n_res = 0

	while n > 0 do
		local path = remove( paths_to_examine, 1 )
		n = n - 1

		if find( path, "[%*%?]" ) then
			-- Find the first path element which contains a wildcard
			local s, e, name = find( path .. "/", "/?([^/]*[%*%?][^/]*)/" )
			local rest = path:sub( e, -1 )


			name = wildcard_to_pattern( name )

			local directory
			if s == 0 then
				directory = "/"
			else
				directory = path:sub( 1, s - 1 ) .. "/"
			end

			local listings, n_ls = ls( directory )

			for i = 1, n_ls do
				local entry = listings[ i ]

				if entry ~= ".." and entry ~= "." and find( entry, name ) then
					n = n + 1
					paths_to_examine[ n ] = directory .. entry .. rest
				end
			end

		elseif is_file( path ) then
			n_res = n_res + 1
			results[ n_res ] = path
		end
	end

	return results, n_res
end

--- The file lookup callback.
-- @param pipeline	description
-- @return io file handle, URI, weight, mode
function plugin.lookup( pipeline )
	local paths, n = find_files( pipeline.filename )
	local result = {}

	for i = 1, n do
		result[i] = { io.open( paths[i], "r" ), paths[i], 0, "*" }
	end

	return result
end
