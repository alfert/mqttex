defmodule MqttexSetTest do
	use ExUnit.Case
	require Lager

	test "fresh and empty Set" do
		s = Mqttex.SubscriberSet.new()
		assert :erlang.element(1, s) == Mqttex.SubscriberSet
		assert 0 == Mqttex.SubscriberSet.size(s)

		e = Mqttex.SubscriberSet.empty(s)
		assert e == s
	end

	test "put one element into the set" do
		s = Mqttex.SubscriberSet.new()
		ep = "/hello/world"
		ev = {"my_client", :fire_and_forget}
		e  = {ep, ev}
		s1 = Mqttex.SubscriberSet.put(s, e)

		assert Mqttex.SubscriberSet.size(s1) == 1
	end

	test "put several elements in the set" do
		s0 = Mqttex.SubscriberSet.new()
		es = [{1, {"/hello/world", {"my_client", :fire_and_forget}}}, 
		 {2, {"/hello/world/x", {"my_client", :fire_and_forget}}},
		 {2, {"/hello/world", {"my_client", :at_least_once}}},
		 {3, {"/hello/+", {"my_client", :fire_and_forget}}},
		 {4, {"/hello/#", {"my_client", :at_least_once}}}
		]

		s2 = Enum.reduce(es, s0, fn({c, e}, s) ->
		 	s1 = Mqttex.SubscriberSet.put(s, e)
		 	c1 = Mqttex.SubscriberSet.size(s1)
			assert c1 == c, "#{c1} == #{c} in Context of\ns1 = #{inspect s1}"
			s1 end
		 	)
		# check with put_all
		s3 = Mqttex.SubscriberSet.put_all(s0, Enum.map(es, &snd/1))

		assert s2 == s3
	end

	test "Check the membership" do 
		s0 = Mqttex.SubscriberSet.new()
		es = will_survive_insert()

		# insert all subscriptions of es
		s = Enum.reduce(es, s0, fn({_, e}, s) -> Mqttex.SubscriberSet.put(s, e) end)
		# check that all subscriptions are there or not	
		Enum.each(es, fn({there?, e}) -> 
			b = Mqttex.SubscriberSet.member?(s, e) 
			assert there? == b,	"#{there?} == #{b}, for e = #{inspect e} in\n #{inspect s}"
			end)
		end

	test "Check the Enum Representation" do 
		s0 = Mqttex.SubscriberSet.new()
		es = will_survive_insert()

		# insert all subscriptions of es
		s = Enum.reduce(es, s0, fn({_, e}, s) -> Mqttex.SubscriberSet.put(s, e) end)

		# check that all subscriptions are there or not	
		Enum.each(s, fn(sub)-> 
			# IO.puts "Check for #{inspect sub}"
			assert Enum.member?(es, {true, sub}), "for sub = #{inspect sub} in\n #{inspect es}"
			end)
		IO.puts "\nThe print function"
		Mqttex.SubscriberSet.print(s)
		IO.puts "The reducer / Enum.each"
		Enum.each(s, fn(e) -> IO.inspect(e) end)
	end

	test "check partial equal function" do
		# es = [{unique_id, subscriber}] where unique_id is equal for "equal" subscriptions
		es = mark_same_prefix

		# check eq function
		Enum.each(es, fn({n, p}) -> 
			Enum.each(es, fn({n1, p1}) -> 
				case (n == n1) do
					true -> assert eq_sub(p, p1)
					false -> assert not eq_sub(p, p1)
				end
			end)
		end)
	end

	test "delete function" do 
		# create a set s of all kind of nodes from list l, but with some node having a common prefix
		# test procedure:
		#   delete an element from set s and from the list l
		#   convert the set es to list ls and show that ls and l are equal if sorted
		l = unique_values()
		Lager.debug "list for deletion #{inspect l}"

		assert 5 == length l

		s0 = Mqttex.SubscriberSet.new()
		# insert all subscriptions of es
		s = Enum.reduce(l, s0, &(Mqttex.SubscriberSet.put(&2, &1)))
		
		:random.seed(:erlang.now())
		indexes = Enum.to_list(5..1) |> Enum.map(&(:random.uniform(&1)-1))
		# indexes = [0, 2, 1, 1, 0]
		Lager.debug "Indexes for deletes: #{inspect indexes}"
		t = fn(_s, [], _i, _n)  -> true
			  (s, l, [i | is], next) -> 
			{:ok, e} = Enum.fetch(l, i)
			Lager.debug "Delete #{inspect e}"
			l1 = List.delete(l, e)
			s1 = Mqttex.SubscriberSet.delete(s, e)
			ls = Enum.to_list(s1)
			assert Enum.sort(ls) == Enum.sort(l1)
			next.(s1, l1, is, next)
			end
		t.(s, l, indexes, t)
		
	end

	defp snd({_a, b}), do: b
	defp fst({a, _b}), do: a

	# defp matchit(a, {a, _b}), do: true
	defp matchit(a, {wild, _b}) do
		wild_re = ("^" <> wild <> "$") |> 
			String.replace("#", ".*") |> 
			String.replace("/+", "/[^/]*")
		Lager.debug("match #{inspect a} with #{wild_re}")
		Regex.compile!(wild_re) |> Regex.match? a
	end

	test "matching of prefixes" do
		l = unique_values()
		s = Enum.reduce(l, Mqttex.SubscriberSet.new(), &(Mqttex.SubscriberSet.put(&2, &1)))

		matches = ["/hello/world", "/hello/world/x", "/hello/"]
		Enum.each(matches, fn(matcher) -> 
			m = Mqttex.SubscriberSet.match(s, matcher) 
			ms = Enum.sort(m)
			fs = Enum.filter(s, &matchit(matcher, &1)) |> Enum.map(&snd/1) |> Enum.sort
			assert ms==fs, "matcher = #{matcher} with ms = #{inspect ms} and fs = #{inspect fs}" 
		end)
	end
	

	test "validity of topic paths" do
		assert ["/", "xxx"] = Mqttex.SubscriberSet.convert_path("/xxx") 
		
		f = fn(x) -> (x |> Mqttex.SubscriberSet.convert_path |> Mqttex.SubscriberSet.join) end
		
		ps = ["/abc/d", "/abc/d/öäü  ,s xcxws / ßksj§", "x/ps/"]
		ps |> Enum.each(&(assert &1 == f.(&1)))
	end

	test "invalidity of topic paths" do
		ps = ["/xxx#", "x+/+", "/akjsdh/+/##"]

		ps |> Enum.each(&(assert {:error, &1} = Mqttex.SubscriberSet.convert_path(&1))) 
	end

	defp clean(p), do: Enum.filter(p, fn(x) -> x != "/" end)

	defp eq_sub({path, {node, _qos1}}, {path, {node, _qos2}}), do: true
	defp eq_sub(_x, _y), do: false 

	def values() do
		[{"/hello/world", {"my_client", :fire_and_forget}},
		 {"/hello/world/x", {"my_client", :fire_and_forget}},
		 {"/hello/world", {"my_client", :at_least_once}},
		 {"/hello/+", {"my_client", :fire_and_forget}},
		 {"/hello/#", {"my_client", :at_least_once}}
		]
	end
	
	def unique_values() do
		uv = Enum.zip(values, 1..Enum.count(values)) |> 
			Enum.map(fn({{p, {c, q}}, n}) -> {p, {"#{c}_#{n}", q}} end)
		Lager.debug ("uv = #{inspect uv}")
		assert Enum.count(values) == Enum.count(uv)
		uv
	end
	
	def mark_same_prefix() do
		# shall contain the same as in check_membership, put_several, check_partial_equal
		pre = values |> Enum.map(fn({p, _}) -> p end) |> 
			Enum.uniq |> 
			Enum.with_index() |> Enum.into %{}
		Lager.debug("#{inspect pre}")
		values |> Enum.map(fn({p, s}) -> {pre[p], {p, s}} end)
	end

 	def will_survive_insert() do
		{_s, l1} = mark_same_prefix |> 
			Enum.to_list |> Enum.reverse |> 
			Enum.reduce({HashSet.new, []}, fn({n, {p, s}}, {set, l}) ->
			case Set.member?(set, n) do
				true -> {set, [{false, {p, s}} | l]}
				false -> {Set.put(set, n), [{true, {p, s}} | l]}
			end
		end)
		l1
	end
	
	
end