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
	defrecordp :sroot,
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
		# End of path component, make a new Leaf with the value
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

	def join({abs, path}), do: join(abs, path)
	def join(true, path),  do: "/#{Enum.join(path, "/")}"
	def join(false, path), do: Enum.join(path, "/")
	
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

end