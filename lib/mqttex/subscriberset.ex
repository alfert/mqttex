defmodule Mqttex.SubscriberSet do
	
	@moduledoc """
	A library module for the set of all subscriptions. Essentially, this datastructure
	implements a set functionality but not as a generic datatructure, but one expects 
	specific data elements. The interface always exprects the following structure

		{topic_path, {client_id, qos}}

	where 

		topic_path :: binary
		client_id  :: binary
		qos        :: atom

	The `topic_path` is path to a topic conforming to wildcards in MQTT (Appendix A) with
	path seperators `/` and wildcards `#` and `+`, respectively. 

	The `client_id` is the identifier for a subscribing to the topic path, and the client 
	does it with the given `qos`. However, the `qos` is not significant for the set, i.e 
	the elements `topic_path` and `client_id` are only used for comparing elements. 

	## Example

	The list of subscriptions is:

		/a/b/c/# -> A
		/d/b/e/+ -> B
		/d/b/e/x -> C
		/d/b     -> F
		/d/y     -> D, E

	The datastructure to hold these subscriptions is (`sroot` omitted:
		
		snode[children: 
		  "/" -> snode[children: 
		    "a" -> snode[children: 
		      "b" -> snode[children:
		      	"c" -> snode[hash: [sleaf(C)]
		      	]
		      ]
		    "d" -> snode[children:
		      "b" -> snode[children: 
		    	"e" -> snode[children: 
		    	  "+" -> snode[leafs: [sleaf(B)]],
		    	  "x" -> snode[leafs: [sleaf(C)]]
		    	  ],
		    	leafs: [sleaf(F)]
		        ],
		      "y" -> snode[leafs: 
		      	[sleaf(D), sleaf(E)]
		      	]
		      ]
		    ]
		  ]
		]

	"""



	# The data structure is a n-ary tree, walking down the path elements. 
	defrecordp :snode, # maps topic_path elements to a list of nodes or leafs
		hash: [] :: [sleaf_t], # list of client with a hash-subscription
		children: HashDict.new  :: Dict.t , # maps each path-prefix to a snode
		leafs: [] :: [sleaf_t] # list of clients 

	# only leafs in the tree hold the value
	defrecordp :sleaf,
		client_id: "" :: binary,
		qos: :fire_and_forget :: :fire_and_forget | :at_least_once | :at_most_once

	# the root node holds the size and the "real" root snode
	defrecordp :sroot, Mqttex.SubscriberSet, 
		size: 0 :: integer,
		root: nil  :: snode_t

	@doc "Returns a new empty SubscriberSet"
	def new(), do: sroot(root: snode())

	@doc "a fresh empty set of the same type"
	def empty(sroot()), do: new()

	@doc "size of the subscriber set"	
	def size(sroot(size: size)), do: size
	
	@doc """
	Inserts an element into the subscriber set. It is checked, that the structure
	of the element fits to the above defined structure
	"""
	def put(sroot(size: size, root: root), _value = {ep, ev}) 
		when is_binary(ep) and is_tuple(ev) and 2 == tuple_size(ev) do # COMPILER BUG
	
		{abs, p} = convert_path(ep)
		{counter, new_root} = do_put(root, abs, p, ev)
		sroot(root: new_root, size: size + counter)
	end
		
	defp do_put(s, true, p, ev) when is_list(p) and is_binary(elem(ev, 0)) and is_atom(elem(ev, 1)) do
		# add a "/" entry on top of p
		do_put(s, ["/" | p], ev)
	end
	defp do_put(s, false, p, ev), do: do_put(s, p, ev) # simple recursive descent

	defp do_put(snode(leafs: ls) = s, [], ev) do
		# end of path component, make a new Leaf with the value
		{counter, ls_new} = add_leaf(ls, ev)
		{counter, snode(s, leafs: ls_new)}
	end
	defp do_put(snode(hash: hs) = s, ["#"], ev) do
		# last path component is a hash, make a new Leaf with the value
		{counter, hs_new} = add_leaf(hs, ev)
		{counter, snode(s, hash: hs_new)}
	end
	defp do_put(snode(children: cs) = s, [p | tail], ev) do
		# inner node handling: 
		# get the current value of key p with default `snode()` as init value
		child = Dict.get(cs, p, snode()) 
		# recursively add the remaining path elements
		{counter, new_child} = do_put(child, tail, ev)
		# replatce the old child with new child in cs
		new_cs = Dict.put(cs, p, new_child)
		# counter is stable, return the modified snode s
		{counter, snode(s, children: new_cs)}
	end

	# adds a new leaf for {c, q} in path p in dictionary dict
	# returns the new dictionary and 0 or 1, i.e. number of new elements
	defp add_leaf(leafs, {c, q}) do
		old_size = length(leafs)
		leaf = sleaf(client_id: c, qos: q)
		# filter out any old subscriptions for the same client and add the new one
		new_leafs = [leaf | Enum.filter(leafs, fn(sleaf(client_id: client) -> client != c) end)]
		{length(new_leafs) - old_size, new_leafs}
	end

	@doc """
	Checks if an element is in the subscriber set. Returns `true` if found, else `false`.
	"""
	def member?(sroot(root: root), {ep, ev}) do
		p = convert_path(ep)
		leafs = find_leafs(root, p)
		# search in leafs for ev
		Enum.any?(leafs, fn(sleaf(client_id: c, qos: q)) -> {c, q} == ev end)
	end
	
	defp find_leafs(s, {true, p}), do: find_leafs(s, ["/" | p])
	defp find_leafs(s, {false, p}), do: find_leafs(s, p)
	defp find_leafs(snode(leafs: ls), []), do: ls
	defp find_leafs(snode(hash: h), ["#"]), do: h
	defp find_leafs(snode(children: cs), [h | tail]) do
		find_leafs(cs[h], tail)
	end

	@doc "Deletes an element from the set"
	# TODO: Test TEST Test! speziell auch das löschen von pfaden
	def delete(sroot(root: root, size: size), {ep, ev}) do
		p = convert_path(ep)
		{new_root, delta, size} = delete(root, p, ev)
		sroot(root: new_root, size: size - delta)
	end
	def delete(snode()=s, {true, p}, ev), do: delete(s, ["/"| p], ev)
	def delete(snode()=s, {false, p}, ev), do: delete(s, p, ev)		
	def delete(snode(leafs: ls)=s, [], ev) do 
		{ls_new, delta, size} = delete_from_list(ls, ev)
		{snode(s, leafs: ls_new), delta, size}
	end
	def delete(snode(hash: hs)=s, ["#"], ev) do 
		{hs_new, delta, size} = delete_from_list(hs, ev)
		{snode(s, hash: hs_new), delta, size}
	end
	def delete(snode(children: cs) = s, [h | tail], ev) do
		{new_cs, delta, size} = delete(cs[h], tail, ev)
		case {delta, size, Dict.size(new_cs)} do 
			{1, 0} -> # cs[h] is empty and can be dropped. 
				# but can we drop the node?
				new_cs = Dict.delete(cs, h)
				lh = length(s.hash)
				ll = length(s.leafs)
				{snode(cs, children: new_cs), 1, lh + ll}
			_  -> {snode(s, children: Dict.put(cs, h, new_cs)), delta, size}
		end	
	end
	

	defp delete_from_list(l, value) do
		size = length(l)
		new_l = List.delete(l, value)
		{new_l, size - length(new_l), length(new_l)}
	end

	@doc "Convert the path into a path list and checks the syntax for MQTT wildcard topic paths"	
	def convert_path(ep) when is_binary(ep) do
		{abs, p} = split(ep)
		case check(p) do
			:ok -> {abs, p}
			_   -> {:error, ep}
		end
	end
	
	# implement split & join locally, since default implementations are platform dependent
	def split(path) do
		p = String.split(path, "/")
		case p do
			["" | tail] -> {true, tail}
			_           -> {false, p}
		end
	end

	def join(true, path),  do: "/#{Enum.join(path, "/")}"
	def join(false, path), do: Enum.join(path, "/")
	def join({abs, path}), do: join(abs, path)
	def join(["/" | path]), do: Enum.join(["/",Enum.join(path, "/")])
	def join(path) when is_list(path), do: Enum.join(path, "/")

	@doc """
	Checks that a splitted path contains wildcard symbols at the proper positions only
	"""
	def check([]), do: :ok
	def check(["#"]), do: :ok
	def check(["+"]), do: :ok
	def check(["+" |tail]), do: check(tail)
	def check([p | tail]) do
		case String.contains?(p, ["+", "#", "/"]) do
			:true  -> :error
			:false -> check(tail)
		end
	end

	def reduce(sroot(root: root), acc, fun) do 
		do_reduce(root, [], acc, fun, fn # next function for the root node
			{:halt, acc} -> {:halted, acc} # stop the reducer from the outside
			{:cont, acc} -> {:done, acc} # we are ready with iterating
			{:suspend, acc} -> {:suspended, acc, &({:done, &1})} # stop after suspend
		end)
	end
	def do_reduce(_s, _p, {:halt, acc}, _fun, _next), do: {:halted, acc}
	def do_reduce(s, p, {:suspend, acc}, fun, next), do: {:suspended, acc, &do_reduce(s, p, &1, fun, next)}
	def do_reduce(snode(leafs: ls, hash: hs, children: cs), p, {:cont, acc}, fun, next) do
		do_reduce_list(ls, p, {:cont, acc}, fun, 
			fn(a1) -> do_reduce_list(hs, ["#" | p], a1, fun, 
				fn(a2) -> do_reduce_dict(Dict.to_list(cs), p, a2, fun, next) end)
			end)
	end	
	def do_reduce(_s, [], acc, _fun, next ) do
		next.(acc) # all elements are done, next of acc will end any iteration.
	end

	# reduce a list of leafs
	def do_reduce_list(_l, _p, {:halt, acc}, _f, _n), do: {:halted, acc}
	def do_reduce_list(l, p, {:suspend, acc}, f, n), do: {:suspended, acc, &do_reduce_list(l, p, &1, f, n)}
	def do_reduce_list([], p, {:cont, acc}, fun, next_after) do 
		# IO.puts("Empty list for path <#{p}>")
		next_after.({:cont, acc})
	end
	def do_reduce_list([sleaf() = head | tail], p, {:cont, acc}, fun, next_after) do
		v = make_value(Enum.reverse(p), head)
		# IO.puts "Value = #{inspect v}"
		do_reduce_list(tail, p, fun.(v, acc), fun, next_after)
	end

	# reduce a dictionary with a dictionary as value
	def do_reduce_dict(_l, _p, {:halt, acc}, _f, _n), do: {:halted, acc}
	def do_reduce_dict(l, p, {:suspend, acc}, f, n), do: {:suspended, acc, &do_reduce_dict(l, p, &1, f, n)}
	def do_reduce_dict([], p, {:cont, acc}, fun, next_after) do 
		next_after.({:cont, acc})
	end
	def do_reduce_dict([h = {p0, s0} | tail], p, {:cont, acc}, fun, next_after) do
		# IO.puts "reduce_dict for #{inspect h} and acc #{inspect acc}"
		do_reduce(s0, [p0 | p], {:cont, acc}, fun,
			&do_reduce_dict(tail, p, &1, fun, next_after))
	end

	@doc """
	Print all elements. 

	This is an example for a reducer-like function.
	"""
	def print(sroot(root: root)), do: print(root, [])

	def print(snode(hash: hs, children: cs, leafs: ls), path) do
		Enum.each(ls, &print(&1, path))
		Enum.each(hs, &print(&1, ["#" | path]))
		Enum.each(cs, fn({k, v}) -> print(v, [k | path]) end)
	end
	def print(sleaf() = l, path) do
		IO.inspect(make_value(Enum.reverse(path), l))
	end

	defp make_value(path, sleaf(client_id: c, qos: q)) do
		{join(path), {c, q}}
	end


	# Implementing the Enum-Interface 
	defimpl Enumerable, for: [Mqttex.SubscriberSet] do
	  	def reduce(set, acc, fun), do: Mqttex.SubscriberSet.reduce(set, acc, fun)
	  	def member?(set, v),       do: { :ok, Mqttex.SubscriberSet.member?(set, v) }
  	  	def count(set),            do: { :ok, Mqttex.SubscriberSet.size(set) }
	end

end