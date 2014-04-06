defmodule MqttexTopicTest do
	# Tests for Topic and TopicManager

	use ExUnit.Case
	require Lager

	@type path :: Mqttex.TopicManager.path
	@type client :: Mqttex.TopicManager.client
	@type qos :: :fire_and_forget | :at_least_once | :exactly_once

	test "fresh and empty subscriptions" do
		s = Mqttex.TopicManager.State.new()
		assert 0 == Mqttex.SubscriberSet.size(s.subscriptions)
		assert Enum.empty? s.topics
		assert Enum.empty? s.clients
	end

 	test "start topic without subscription" do
		s0 = Mqttex.TopicManager.State.new()
		{s1, c}  = Mqttex.TopicManager.manage_topic_start("hello", s0)
		assert 0 == Mqttex.SubscriberSet.size(s1.subscriptions)
		assert ["hello"] == Enum.to_list(s1.topics)
		assert Enum.empty? s1.clients
		assert Enum.empty? c
 	end

	test "simple subscription of not started topic" do
		s0 = Mqttex.TopicManager.State.new()
		{s1, t} = Mqttex.TopicManager.manage_subscriptions([{"hello", :fire_and_forget}], "clientA", s0)
		assert 1 == Mqttex.SubscriberSet.size(s1.subscriptions)
		assert Enum.empty? s1.topics
		assert ["clientA"] == Dict.keys(s1.clients)
		assert Enum.empty? t
 	end

 	test "simple subscription and start" do
		s0 = Mqttex.TopicManager.State.new()
		{s1, t} = Mqttex.TopicManager.manage_subscriptions([{"hello", :fire_and_forget}], "clientA", s0)
		s2  = Mqttex.TopicManager.manage_topic_start("hello", s1)
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

end