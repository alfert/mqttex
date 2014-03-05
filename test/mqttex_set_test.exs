defmodule MqttexSetTest do
	use ExUnit.Case
	require Lager

	test "fresh and empty Set" do
		s = Mqttex.SubscriberSet.new()
		assert :erlang.element(1, s) == :sroot
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
		#IO.inspect s1
	end

	test "put several elements in the set" do
		s0 = Mqttex.SubscriberSet.new()
		es = [{1, {"/hello/world", {"my_client", :fire_and_forget}}}, 
		 {2, {"/hello/world/x", {"my_client", :fire_and_forget}}},
		 {2, {"/hello/world", {"my_client", :at_least_once}}},
		 {3, {"/hello/+", {"my_client", :fire_and_forget}}},
		 {4, {"/hello/#", {"my_client", :at_least_once}}}
		]

		 Enum.reduce(es, s0, fn({c, e}, s) ->
		 	s1 = Mqttex.SubscriberSet.put(s, e)
		 	c1 = Mqttex.SubscriberSet.size(s1)
			assert c1 == c, "#{c1} == #{c} in Context of\ns1 = #{inspect s1}"
			s1 end
		 	)
	end

	test "validity of topic paths" do
		assert {true, p} = Mqttex.SubscriberSet.convert_path("/xxx") 
		
		f = fn(x) -> (x |> Mqttex.SubscriberSet.convert_path |> Mqttex.SubscriberSet.join) end
		
		ps = ["/abc/d", "/abc/d/öäü  ,s xcxws / ßksj§", "x/ps/"]
		ps |> Enum.each(&(assert &1 == f.(&1)))
	end

	test "invalidity of topic paths" do
		ps = ["/xxx#", "x+/+", "/akjsdh/+/##"]

		ps |> Enum.each(&(assert {:error, &1} = Mqttex.SubscriberSet.convert_path(&1))) 
	end

	defp clean(p), do: Enum.filter(p, fn(x) -> x != "/" end)
end