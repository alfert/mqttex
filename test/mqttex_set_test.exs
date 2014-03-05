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

	test "put two elements in the set" do
		s = Mqttex.SubscriberSet.new()
		e1 = {"/hello/world", {"my_client", :fire_and_forget}}
		s1 = Mqttex.SubscriberSet.put(s, e1)

		assert Mqttex.SubscriberSet.size(s1) == 1

		e2 = {"/hello/world/x", {"my_client", :fire_and_forget}}
		s2 = Mqttex.SubscriberSet.put(s1, e2)

		assert Mqttex.SubscriberSet.size(s2) == 2
		# IO.inspect s2

		e3 = {"/hello/world", {"my_client", :at_least_once}}
		s3 = Mqttex.SubscriberSet.put(s2, e3)
		IO.inspect s3
		assert Mqttex.SubscriberSet.size(s3) == 2	
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