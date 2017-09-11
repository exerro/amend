
local Task = {}
local super_task

local function new_tree( task, parent )
	return {
		task = task,
		parent = parent,
		replacers = {},
		children = {}
	}
end

local function get_tree( tasks )
	local tree = new_tree( super_task )
	local tree_lookup = { [super_task.name] = tree }

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
						replacee.replacers[#replacee.replacers + 1] = tree
						tree_lookup[task.name] = tree
						table.remove( tasks, i )
					else
						return error( "mismatched parents: " .. task.name .. " replaces " .. tree_lookup[task._replaces].task.name .. " but doesn't share a parent (" .. task._within .. " != " .. tree_lookup[task._replaces].task._within .. ")", 0 )
					end
				elseif not task._replaces then
					local tree = new_tree( task, within )
					tree_lookup[within].children[#tree_lookup[within].children + 1] = tree
					tree_lookup[task.name] = tree
					table.remove( tasks, i )
				end
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

	return tree
end

local function serialize_tree( tree )
	local c = {}
	local r = {}

	for i = 1, #tree.children do
		c[i] = serialize_tree( tree.children[i] )
	end

	for i = 1, #tree.replacers do
		r[i] = serialize_tree( tree.replacers[i] )
	end

	return (c[1] and "[" .. table.concat( c, ", " ) .. "] " or "") .. (r[1] and "{" .. table.concat( r, ", " ) .. "} " or "") .. tree.task.name
end

function Task:new( name )
	local task = setmetatable( {}, { __index = self } )
	task.name = name
	task._within = nil
	task._replaces = nil
	task._reorder = nil
	task.order = {}
	task._takes = nil
	task._returns = nil
	task._labels = {}
	return task
end

function Task.construct_task_list( tasks )
	local tree = get_tree( tasks )
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
	self.order[#self.order + 1] = { "before", task }
	return self
end

function Task:after( task )
	self.order[#self.order + 1] = { "after", task }
	return self
end

function Task:at( label )
	self.order[#self.order + 1] = { "at", label }
	return self
end

function Task:labels( labels )
	self._labels = labels
	return self
end

function Task:reorder( order )
	self._reorder = order
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
	:labels { "stream", "parse_origin", "transform_origin", "compile_origin", "parse", "transform", "pre-merge" }

--[[ Testing ]]-----------------------------------------------------------------
local h = fs.open( "/amend/log.txt", "w" )
h.write( serialize_tree( get_tree {
	Task "custom_macro_expansion" :within "root" :replaces "macro_expansion",
	Task "variable_lookup" :within "transform",
	Task "macro_expansion" :within "transform",
	Task "transform" :within "boop",
} ) )
h.close()
--[[ End of testing ]]----------------------------------------------------------

return Task
