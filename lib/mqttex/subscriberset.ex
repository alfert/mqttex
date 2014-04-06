defmodule Mqttex.SubscriberSet do

	require Lager	

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

	@typedoc "A splitted path which first components `true` for an absolute path"
	@opaque subscription_set :: sroot_t
	@type client :: binary
	@type subscriber :: {  client, Mqttex.qos_type } 
	@type path :: binary
	@type splitted_path ::[binary]
	@type subscription :: { path, subscriber }

	# The data structure is a n-ary tree, walking down the path elements. 
	defrecordp :snode, # maps topic_path elements to a list of nodes or leafs
		hash: [] :: [sleaf_t], # list of client with a hash-subscription
		children: HashDict.new  :: Dict.t , # maps each path-prefix to a snode
		leafs: [] :: [sleaf_t] # list of clients 

	# only leafs in the tree hold the value
	defrecordp :sleaf,
		client_id: "" :: binary,
		qos: :fire_and_forget :: Mqttex.qos_type

	# the root node holds the size and the "real" root snode
	defrecordp :sroot, Mqttex.SubscriberSet, 
		size: 0 :: integer,
		root: nil  :: snode_t

	@doc "Returns a new empty SubscriberSet"
	@spec new :: subscription_set
	def new(), do: sroot(root: snode())

	@doc "a fresh empty set of the same type"
	@spec empty(subscription_set) :: subscription_set
	def empty(sroot()), do: new()

	@doc "size of the subscriber set"	
	@spec size(subscription_set) :: non_neg_integer
	def size(sroot(size: size)), do: size


	@doc """
	Matches a topic path with all subscriptions and returns all matched clients. 

	A topic path does not have any wildcards. But the wildcards in the subscriptions
	are used to identify all interested clients. 
	"""
	@spec match(subscription_set, path) :: [subscriber]
	def match(s = sroot(root: root), topic_path) do
		# Lager.info "match of path #{topic_path}"
		p = split(topic_path)
		do_match(root, p, []) |> List.flatten
	end
	
	defp do_match(snode(leafs: ls), [], acc), do: [get_leafs(ls) | acc]
	defp do_match(snode(hash: hs, children: cs), [p | tail], acc) do
		acc1 = [get_leafs(hs) | acc]
		acc2 = case Dict.fetch(cs, p) do
			{:ok, node} -> 
				# Lager.info("Found #{inspect p}")
				do_match(node, tail, acc1)
			:error      -> acc1
		end
		case Dict.fetch(cs, "+") do
			{:ok, plus_node} -> 
				# Lager.info("Found + for #{inspect p}")
				do_match(plus_node, tail, acc2)
			:error -> acc2
		end
	end
	
	defp get_leafs(ls) do
		Enum.map(ls, fn(sleaf(client_id: c, qos: q)) -> {c, q} end)
	end	

	@doc """
	Adds a list of subscriptions to the set
	"""
	@spec put_all(subscription_set, [subscription]) :: subscription_set
	def put_all(set, subs) do
		Enum.reduce(subs, set, &(put(&2, &1)))
	end
	

	@doc """
	Inserts an element into the subscriber set. 

	It is checked, that the structure of the element fits to the above defined structure.
	"""
	@spec put(subscription_set, subscription) :: subscription_set
	def put(set = sroot(size: size, root: root), _value = {ep, ev}) 
		when is_binary(ep) and is_tuple(ev) and 2 == tuple_size(ev) do # COMPILER BUG
	
		p = convert_path(ep)
		{counter, new_root} = do_put(root, p, ev)
		sroot(root: new_root, size: size + counter)
	end
		
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
	@spec member?(subscription_set, subscription) :: boolean
	def member?(_set = sroot(root: root), _element = {ep, ev}) do
		p = convert_path(ep)
		leafs = find_leafs(root, p)
		# search in leafs for ev
		Enum.any?(leafs, fn(sleaf(client_id: c, qos: q)) -> {c, q} == ev end)
	end
	
	defp find_leafs(snode(leafs: ls), []), do: ls
	defp find_leafs(snode(hash: h), ["#"]), do: h
	defp find_leafs(snode(children: cs), [h | tail]) do
		find_leafs(cs[h], tail)
	end

	@doc "Deletes an element from the set"
	@spec delete(subscription_set, subscription) :: subscription_set
	def delete(sroot(root: root, size: size), {ep, ev}) do
		p = convert_path(ep)
		{new_root, delta, size} = delete(root, p, ev)
		sroot(root: new_root, size: size - delta)
	end
	defp delete(snode(leafs: ls)=s, [], ev) do 
		Lager.debug("delete - leafs = #{inspect ls}, path  = []")
		{ls_new, delta, size} = delete_from_list(ls, ev)
		Lager.debug("delete - new_leafs = #{inspect ls_new}, path  = []")
		new_s = snode(s, leafs: ls_new)
		{new_s, delta, size_snode(new_s)}
	end
	defp delete(snode(hash: hs)=s, ["#"], ev) do 
		{hs_new, delta, size} = delete_from_list(hs, ev)
		new_s = snode(s, hash: hs_new)
		{new_s, delta, size_snode(new_s)}
	end
	defp delete(snode(children: cs) = s, [h | tail], ev) do
		Lager.debug("delete - children = #{inspect cs}, path  = #{inspect h}")
		{new_cs_h, delta, size} = delete(cs[h], tail, ev)
		lh = length(snode(s, :hash))
		ll = length(snode(s, :leafs))
		case {delta, size} do 
			{1, 0} -> # cs[h] is empty and can be dropped. 
				Lager.debug("Drop cs[#{inspect h}]")
				new_cs = Dict.delete(cs, h)
				Lager.debug("new_cs is #{inspect new_cs}")
				new_s = snode(s, children: new_cs)
				Lager.debug("new snode is #{inspect new_s}")
				{new_s, 1, size_snode(new_s)}
			_  -> 
				Lager.debug("Update cs[#{inspect h}]")
				new_s = snode(s, children: Dict.put(cs, h, new_cs_h))
				{new_s, delta, size_snode(new_s) }
		end	
	end

	# returns the number of the snode's outgoing elements (leafs, children, hashes)
	defp size_snode(snode(hash: hs, children: cs, leafs: ls)) do
		length(hs) + length(ls) + Dict.size(cs)
	end
	defp size_snode(any) do
		Lager.error("size_snode got argument #{inspect any}")
		0 = 1
	end

	defp delete_from_list(l, {client, _qos}) do
		Lager.debug("delete_from_list: client = #{inspect client} from #{inspect l}")
		size = length(l)
		new_l = Enum.filter(l, 
			fn  (sleaf(client_id: c)) when c == client -> false
				(_ ) -> true end)
		{new_l, size - length(new_l), length(new_l)}
	end

	@doc "Convert the path into a path list and checks the syntax for MQTT wildcard topic paths"
	@spec convert_path(path) :: splitted_path | {:error, path}
	def convert_path(ep) when is_binary(ep) do
		p = split(ep)
		case check(p) do
			:ok -> p
			_   -> {:error, ep}
		end
	end
	
	@doc """
	Checks that a splitted path contains wildcard symbols at the proper positions only
	"""
	@spec check([binary]) :: :ok | :error
	def check([]), do: :ok
	def check(["#"]), do: :ok
	def check(["+"]), do: :ok
	def check(["+" |tail]), do: check(tail)
	def check(["/" |tail]), do: check(tail)
	def check([p | tail]) do
		case String.contains?(p, ["+", "#", "/"]) do
			:true  -> :error
			:false -> check(tail)
		end
	end

	# implement split & join locally, since default implementations are platform dependent
	@doc """
	Splits a path into its sub-elements. 

	If the path is absolute (i.e. with leading `"/"`), returns true as first component. 
	"""
	@spec split(path) :: splitted_path
	def split(path) do
		p = String.split(path, "/")
		case p do
			["" | tail] -> ["/" | tail]
			_           -> p
		end
	end

	@doc "Joins a splitted path back to its string representation."
	def join(["/" | path]), do: Enum.join(["/",Enum.join(path, "/")])
	def join(path) when is_list(path), do: Enum.join(path, "/")

	

	@doc """
	Reducer-function for implementing the `Enumerable` protocol. 

	"""
	@spec reduce(subscription_set, any, any :: any) :: any
	def reduce(set = sroot(root: root), acc, fun) do 
		do_reduce(root, [], acc, fun, fn # next function for the root node
			{:halt, acc} -> {:halted, acc} # stop the reducer from the outside
			{:cont, acc} -> {:done, acc} # we are ready with iterating
			{:suspend, acc} -> {:suspended, acc, &({:done, &1})} # stop after suspend
		end)
	end
	defp do_reduce(_s, _p, {:halt, acc}, _fun, _next), do: {:halted, acc}
	defp do_reduce(s, p, {:suspend, acc}, fun, next), do: {:suspended, acc, &do_reduce(s, p, &1, fun, next)}
	defp do_reduce(snode(leafs: ls, hash: hs, children: cs), p, {:cont, acc}, fun, next) do
		do_reduce_list(ls, p, {:cont, acc}, fun, 
			fn(a1) -> do_reduce_list(hs, ["#" | p], a1, fun, 
				fn(a2) -> do_reduce_dict(Dict.to_list(cs), p, a2, fun, next) end)
			end)
	end	
	defp do_reduce(_s, [], acc, _fun, next ) do
		next.(acc) # all elements are done, next of acc will end any iteration.
	end

	# reduce a list of leafs
	defp do_reduce_list(_l, _p, {:halt, acc}, _f, _n), do: {:halted, acc}
	defp do_reduce_list(l, p, {:suspend, acc}, f, n), do: {:suspended, acc, &do_reduce_list(l, p, &1, f, n)}
	defp do_reduce_list([], p, {:cont, acc}, fun, next_after) do 
		# IO.puts("Empty list for path <#{p}>")
		next_after.({:cont, acc})
	end
	defp do_reduce_list([sleaf() = head | tail], p, {:cont, acc}, fun, next_after) do
		v = make_value(Enum.reverse(p), head)
		# IO.puts "Value = #{inspect v}"
		do_reduce_list(tail, p, fun.(v, acc), fun, next_after)
	end

	# reduce a dictionary with a dictionary as value
	defp do_reduce_dict(_l, _p, {:halt, acc}, _f, _n), do: {:halted, acc}
	defp do_reduce_dict(l, p, {:suspend, acc}, f, n), do: {:suspended, acc, &do_reduce_dict(l, p, &1, f, n)}
	defp do_reduce_dict([], p, {:cont, acc}, fun, next_after) do 
		next_after.({:cont, acc})
	end
	defp do_reduce_dict([h = {p0, s0} | tail], p, {:cont, acc}, fun, next_after) do
		# IO.puts "reduce_dict for #{inspect h} and acc #{inspect acc}"
		do_reduce(s0, [p0 | p], {:cont, acc}, fun,
			&do_reduce_dict(tail, p, &1, fun, next_after))
	end

	@doc """
	Print all elements. 

	This is an example for a reducer-like function, which can easily implemented via `Enum`: 

		Enum.each(s, &IO.inspect(&1))

	"""
	@spec print(subscription_set) :: :ok
	def print(sroot(root: root)), do: print(root, [])

	defp print(snode(hash: hs, children: cs, leafs: ls), path) do
		Enum.each(ls, &print(&1, path))
		Enum.each(hs, &print(&1, ["#" | path]))
		Enum.each(cs, fn({k, v}) -> print(v, [k | path]) end)
	end
	defp print(sleaf() = l, path) do
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