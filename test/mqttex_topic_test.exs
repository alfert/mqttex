defmodule MqttexTopicTest do
	# Tests for Topic and TopicManager

	use ExUnit.Case
	require Lager

	@type path :: Mqttex.TopicManager.path
	@type client :: Mqttex.TopicManager.client
	@type qos :: :fire_and_forget | :at_least_once | :exactly_once

	test "fresh and empty subscriptions" do
		s = %Mqttex.TopicManager{}
		assert 0 == Mqttex.SubscriberSet.size(s.subscriptions)
		assert Enum.empty? s.topics
		assert Enum.empty? s.clients
	end

 	test "start topic without subscription" do
		s0 = %Mqttex.TopicManager{}
		{s1, c}  = Mqttex.TopicManager.manage_topic_start("hello", s0)
		assert 0 == Mqttex.SubscriberSet.size(s1.subscriptions)
		assert ["hello"] == Enum.to_list(s1.topics)
		assert Enum.empty? s1.clients
		assert Enum.empty? c
 	end

	test "simple subscription of not started topic" do
		s0 = %Mqttex.TopicManager{}
		{s1, t} = Mqttex.TopicManager.manage_subscriptions([{"hello", :fire_and_forget}], "clientA", s0)
		assert 1 == Mqttex.SubscriberSet.size(s1.subscriptions)
		assert Enum.empty? s1.topics
		assert ["clientA"] == Dict.keys(s1.clients)
		assert Enum.empty? t
 	end

 	test "simple subscription and start" do
		s0 = %Mqttex.TopicManager{}
		{s1, t} = Mqttex.TopicManager.manage_subscriptions([{"hello", :fire_and_forget}], "clientA", s0)
		{s2, c} = Mqttex.TopicManager.manage_topic_start("hello", s1)

		assert Enum.empty? t
		assert ["hello"] == Set.to_list(s2.topics)
		assert ["clientA"] == Dict.keys(s2.clients)
	end

	test "subscribe many and start some" do
		# prepare initial subscriptions
		s0 = %Mqttex.TopicManager{}
		{s1, ts} = Enum.reduce(unique_values, {s0, []}, fn({topic, {c, q}}, {s, _}) -> 
			Mqttex.TopicManager.manage_subscriptions([{topic, q}], c, s)
		end)

		# ensure that not clients are subscribed to existing topics (they are none!)
		assert Enum.empty? s1.topics
		assert Enum.count(unique_values) ==  Enum.count s1.clients
		Enum.each(s1.clients, fn({k, v}) -> 
			assert Enum.empty?(v), "Enum.empty? for key #{k}" end)
		assert Enum.empty? ts

		# start topics and check the subscribed clients
		l = [{"unkwown topic", []}, {"/hello/world/x", [2, 5]}]
		Enum.reduce(l, s1, fn({topic, sub_index}, s_acc) -> 
			# start topic
			{sn, _} = Mqttex.TopicManager.manage_topic_start(topic, s_acc)
			# check that all sub_indexes are subscribers 
			Enum.each(sub_index, fn(i) -> 
				topics = Dict.get(sn.clients, "my_client_#{i}", HashSet.new)
				assert Set.member?(topics, topic)
			end)
			# if no sub_index, then also no subscribers available
			assert (Enum.empty?(sub_index) |> implies (
				Dict.keys(sn.clients) |> Enum.each(fn(topics) -> not Set.member?(sn.topics, topic) end))),
				"sub_index #{inspect sub_index} ==> topic = #{topic} and #{inspect sn.clients}"
			sn
		end)
	end

	# values of subscriptions
	@spec values() :: [{path, {client, qos}}]
	def values() do
		[{"/hello/world", {"my_client", :fire_and_forget}}, 
		 {"/hello/world/x", {"my_client", :fire_and_forget}},
		 {"/hello/world", {"my_client", :at_least_once}},
		 {"/hello/+", {"my_client", :fire_and_forget}},
		 {"/hello/#", {"my_client", :at_least_once}}
		]
	end
	
	# renames the client such that all subscriptions are unique concerning the client
	def unique_values() do
		Enum.zip(values, 1..Enum.count(values)) |> 
			Enum.map(fn({{p, {c, q}}, n}) -> {p, {"#{c}_#{n}", q}} end)
	end

	def implies(a, b) do
		if a, do: b, else: true
	end
	

end