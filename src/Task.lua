
local Task = {}
local super_task

local function parse_reorder_string( str )
	local s, f, n = str:find "%s*(%S+)%s*%->"
	local of = f and f + 1 or 1
	local t = { { n, false } }
	while s do
		s, f, n = str:find( "%s*(%S+)%s*%->", f + 1 )
		t[#t][2] = n
		if s then
			of = f + 1
			t[#t + 1] = { n, false }
		end
	end
	t[#t][2] = str:match( "(%S+)", of )
	return t
end

local function get_constraints( trees )
	local constraints = {}

	for i = 1, #trees do
		local tree = trees[i]
		for j = 1, #tree.task._order do
			local order = tree.task._order[j]
			constraints[#constraints + 1] = order[1] == "before" and { tree.task.name, order[2] } or { order[2], tree.task.name }
		end
	end

	for i = 1, #constraints do
		print( tostring( constraints[i][1] ) .. " -> " .. tostring( constraints[i][2] ) )
	end

	return constraints
end

local function sort_task_list( t, constraints )

end

local function new_tree( task, parent )
	return {
		task = task,
		parent = parent,
		replacers = {},
		enabled = not task._optional,
		children = {}
	}
end

local function get_tree( tasks )
	local tree = new_tree( super_task )
	local tree_lookup = { [super_task.name] = tree }
	local dependencies = {}

	while #tasks > 0 do
		local lastl = #tasks

		for i = #tasks, 1, -1 do
			local task = tasks[i]
			local within = task._within or "root"

			if tree_lookup[within] then
				if task._replaces and tree_lookup[task._replaces] then
					if tree_lookup[task._replaces].parent == within or not task._within then
						local replacee = tree_lookup[task._replaces]
						local tree = new_tree( task, replacee.parent )
						tree.children = tree_lookup[task._replaces].children
						replacee.replacers[#replacee.replacers + 1] = tree
						tree_lookup[task.name] = tree
						table.remove( tasks, i )
					else
						return error( "mismatched parents: " .. task.name .. " replaces " .. tree_lookup[task._replaces].task.name .. " but doesn't share a parent (" .. task._within .. " != " .. tree_lookup[task._replaces].task._within .. ")", 0 )
					end
				elseif not task._replaces then
					local tree = new_tree( task, within )
					tree_lookup[within].children[#tree_lookup[within].children + 1] = tree
					tree_lookup[within].enabled = true
					tree_lookup[task.name] = tree
					table.remove( tasks, i )
				end

				local d = task._dependencies
				for i = 1, #d do
					local t = dependencies[d[i].name]
					if not t then
						t = {}
						dependencies[d[i].name] = t
					end
					if d[i].required then
						t[#t + 1] = task.name
					end
				end
			end
		end

		for k, v in pairs( dependencies ) do
			if tree_lookup[k] then
				tree_lookup[k].enabled = true
			elseif #v > 0 then
				return error( "Task '" .. k .. "' required by '" .. table.concat( v, "', '" ) .. "' but not found", 0 )
			end
		end

		if lastl == #tasks then -- cyclic dependency or something
			local lookup = {}
			local checked = {}

			local function check( name )
				checked[#checked + 1] = name
				if lookup[name] then
					return "cyclic parent reference: " .. table.concat( checked, " in ", lookup[name] )
				end
				lookup[name] = #checked
				for i = 1, #tasks do
					if tasks[i].name == name then
						return check( tasks[i]._within or "root" )
					end
				end
				if name ~= "root" then
					return "unresolved dependency: " .. name
				end
			end

			local err = check( tasks[1].name )
			if err then
				return error( err, 0 )
			end

			for i = 2, #tasks do
				if not tree_lookup[tasks[i]._within or "root"] then
					local f = false
					for j = 1, #tasks do
						if tasks[j].name == tasks[i]._within then
							f = true
						end
					end
					if not f then
						return error( "unresolved dependency: " .. tasks[i]._within )
					end
				end
			end

			return "oh no"
		end
	end

	local function disable_recursive( t )
		if #t.replacers > 0 then
			t.enabled = false
		end

		for i = 1, #t.children do
			disable_recursive( t.children[i] )
		end
	end

	disable_recursive( tree )

	return tree
end

function Task:new( name )
	local task = setmetatable( {}, { __index = self } )
	task.name = name
	task._within = nil
	task._replaces = nil
	task._reorder = nil
	task._order = {}
	task._dependencies = {}
	task._takes = nil
	task._returns = nil
	task._optional = false
	return task
end

function Task.generate_pipeline( tasks )
	local tree = get_tree( tasks )
	-- the tree children ordering
	-- generate sequential list of tasks and return it
end

function Task:takes( datatype )
	self._takes = datatype
	return self
end

function Task:returns( datatype )
	self._returns = datatype
	return self
end

function Task:on( datatype )
	self._takes = datatype
	self._returns = datatype
	return self
end

Task.eats = Task.takes
Task.poops = Task.returns

function Task:within( task )
	self._within = task
	return self
end

function Task:replaces( task )
	self._replaces = task
	return self
end

function Task:before( task )
	self._dependencies[#self._dependencies + 1] = { name = task, required = false }
	self._order[#self._order + 1] = { "before", task }
	return self
end

function Task:after( task )
	self._dependencies[#self._dependencies + 1] = { name = task, required = false }
	self._order[#self._order + 1] = { "after", task }
	return self
end

function Task:reorder( order )
	self._reorder = order
	return self
end

function Task:optional( v )
	self._optional = v == nil and true or v
	return self
end

function Task:requires( task )
	self._dependencies[#self._dependencies + 1] = { name = task, required = true }
	return self
end

function Task:enables( task )
	self._dependencies[#self._dependencies + 1] = { name = task, required = false }
	return self
end

function Task:instance()
	return {
		task = self,
		subtasks = {},
		disabled = false
	}
end

setmetatable( Task, { __call = Task.new } )

super_task = Task "root"
	:takes "URI"
	:returns "AST"

--[[ Testing ]]-----------------------------------------------------------------
local function serialize_tree( tree )
	local c = {}
	local r = {}

	for i = 1, #tree.children do
		c[i] = serialize_tree( tree.children[i] )
	end

	for i = 1, #tree.replacers do
		r[i] = serialize_tree( tree.replacers[i] )
	end

	return (c[1] and "[" .. table.concat( c, ", " ) .. "] " or "") .. (r[1] and "{" .. table.concat( r, ", " ) .. "} " or "") .. (tree.enabled and "" or "!") .. tree.task.name
end

Task.generate_pipeline( {
	Task "A",
	Task "B" :after "A",
	Task "C" :after "A",
	Task "D" :after "C",
	Task "E" :after "D" :after "C"
} )

local t = parse_reorder_string "a -> b -> c -> d"

for i = 1, #t do
	t[i] = tostring( t[i][1] ) .. " -> " .. tostring( t[i][2] )
end

--[[ End of testing ]]----------------------------------------------------------

return Task
