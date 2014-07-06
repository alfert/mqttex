defmodule Mqttex.TopicManager do
	
	@moduledoc """
	The topic manager has two important tasks: 

	* dispatching incoming messages to their topics
	* managing subscriptions, in particular wildcard subscriptions

	## Wildcard subscriptions

	### Subscribing
	If a client subscribes with a topic wildcard, we store a mapping of 
	`{topic wildcard, client}` in the list of subscription. After that, 
	we match the topic wildcard with the list of all existing topics 
	and subscribe the client to all matched topics. 

	### Starting a new topic
	If a new topic is started, we match all (wildcard) subscriptions to
	find all client which already subscribed to the (yet not existing) topic. 
	All match clients are subscribed by the topic. This process is initiated
	by the `Topic` implementation as part of booting the topic process. 

	### Unsubscribing 
	If a client unsubscribes a (wildcard) topic, we match the topic (wildcard) 
	with all existing topics and unsubscribe the client from the matched topics. 

	"""

	use GenServer
	require Lager

	@my_name __MODULE__

	@type topic :: binary
	@type client :: binary
	defstruct subscriptions: Mqttex.SubscriberSet.new, # map topic_wildcard to {client, qos}
		topics: HashSet.new, #  all existing (non-wildcard) topics
		clients: HashDict.new 
	# 	do # maps client to their subscribed topics
	# 	record_type subscriptions: Mqttex.SubscriberSet.subscription_set,
	# 		topics: Set.t(Mqttex.TopicManager.topic),
	# 		clients: Dict.t(Mqttex.TopicManager.client, [Mqttex.TopicManager.topic])
	# end

	@doc """
	Publishing a messages means dispatching to topic. If the topic does not 
	exist yet, it is started. 
	"""
	@spec publish(Mqttex.Msg.Publish.t, binary) :: :ok
	def publish(%Mqttex.Msg.Publish{} = msg, from) do
		# if the topic exists, publish it directly without 
		# interfering with the topic manager.
		try do
			Mqttex.Topic.publish(msg, from)
		catch
			# Topic does not exist, so start it. 
			:exit, {:no_proc, _} -> 
				start_topic(msg, from)
				Mqttex.Topic.publish(msg, from)
			any -> throw any
		end
	end
	
	@doc """
	Starts explicitely a topic from a `PublisgMsg` and publishes
	the message.
	"""
	def start_topic(%Mqttex.Msg.Publish{} = msg, from) do
		:gen_server.call(@my_name, {:start_topic, msg, from})
	end
	
	@doc """
	Handles a subscription message from a client. 

	Returns the list of granted qos types. 
	"""
	@spec subscribe(Mqttex.Msg.Subscribe.t, binary) :: [Mqttex.qos_type]
	def subscribe(%Mqttex.Msg.Subscribe{} = topics, from) do
		:gen_server.call(@my_name, {:subscribe, topics, from})
	end
	
	def start_link() do
		:gen_server.start_link({:local, @my_name}, __MODULE__, [], [])
	end
	
	#################################################################################
	#### Call Backs
	#################################################################################
	def init([]) do
		# IO.puts "Init of TopicManager"
		{:ok, %Mqttex.TopicManager{} }
	end

	def handle_call({:start_topic, %Mqttex.Msg.Publish{topic: topic} = _msg, _from}, _, 
						%Mqttex.TopicManager{} = state) do
		# ignore any problems during start, in particular :already_started
		# because we call the topic server via its name. Any problems happening
		# from concurrent starts of the topics are resolved here: after start_topic
		# the topic must be there. Otherwise we have a severe problem to be solved
		# somewhere else.
		:ok = case Mqttex.SubTopic.start_topic(topic) do
			{:ok, _pid} -> :ok
			{:ok, _pid, _info} -> :ok
			{:error, {:already_started, _child}} -> :ok
			any -> any
		end
		{new_state, subscribed_clients} = manage_topic_start(topic, state)
		Enum.each(subscribed_clients, fn({c, q}) -> Mqttex.Topic.subscribe(topic, q, c)end)
		{:return, :ok, new_state}
	end
	def handle_call({:subscribe, %Mqttex.Msg.Subscribe{topics: topics}, _from}, client, state) do
		# manage the state ...
		{new_state, new_topics} = manage_subscriptions(topics, client, state)

		# subscribe to all new topics
		Enum.each(new_topics, fn(t, q) -> Mqttex.Topic.subscribe(t, q, client) end)

		# We support any type of QoS, thus the granted list contains simply the requested qos
		granted = Enum.map(topics, fn(_topic, qos) -> qos end)
		{:return, granted, new_state}
	end
	
	@doc """
	Adds the new subscriptions to the already existing subscriptions in state.

	Returns the new state and list of newly subscribed topics
	"""
	@spec manage_subscriptions([{topic, Mqttex.qos_type}], client, TopicManager.t):: {TopicManager.t, [topic]}
	def manage_subscriptions(topics, client, state = %Mqttex.TopicManager{clients: clients, topics: all_topics}) do
		# topics contains wildcards and others. Store them in to the new state
		# topics is list of {wildcard, qos}
		subs = Mqttex.SubscriberSet.put_all(state.subscriptions, 
			Enum.map(topics, fn({topic, qos}) -> {topic, {client, qos}} end))
		new_state = %Mqttex.TopicManager{state | subscriptions: subs}
		
		# identify all (new) already existing topics to that the client 
		# is subscribing. 
		subscribed_topics = Dict.get(clients, client, HashSet.new)
		new_topics = all_topics |> 
			Enum.filter(fn(t) -> not Enum.member?(subscribed_topics, t) end) |>
			# .. only not to client subscribed topics here ==> testing!
			# match them
			Enum.reduce(HashSet.new, fn(t, acc) -> 
				cs = all_subscribers_of_topic(subs, t)
				case Enum.member?(cs, t) do
					true -> Set.put(acc, t)
					false -> acc
				end
			end)
		new_state1 = %Mqttex.TopicManager{ new_state | clients: Dict.update(clients, client, new_topics,
			fn(v) -> Set.put_all(v, Enum.map(new_topics, &(&1))) end)}
		{new_state1, new_topics}
	end
	

	def manage_topic_start(topic, %Mqttex.TopicManager{topics: topics} = state) do
		# add the new topic to all existings topics
		new_state = %Mqttex.TopicManager{state | topics: Set.put(topics, topic)}
		# find all subscribers
		subscribed_clients = all_subscribers_of_topic(new_state, topic)
		Lager.debug("New State = #{inspect new_state}")
		# update the subscriptions of all subscribers of the new topic
		new_clients = subscribed_clients |> 
			Enum.reduce(new_state.clients, fn({client, _qos}, cs) -> 
				# update the dict of client->topics
				Dict.update(cs, client, Enum.into([topic], HashSet.new), &(Set.put(&1, topic)))
			end)
		{%Mqttex.TopicManager{new_state | clients: new_clients}, subscribed_clients}
	end
	

	@doc """
	Returns a list of process ids for all clients subscribed to this topic. Resolves
	wildcard topic subscription. 
	"""
	@spec all_subscribers_of_topic(TopicManager.t | Mqttex.SubscriberSet.subscription_set, topic) :: [{client, Mqttex.qos_type}] 
	def all_subscribers_of_topic(%Mqttex.TopicManager{subscriptions: sub}, topic), do: all_subscribers_of_topic(sub, topic)
	def all_subscribers_of_topic(sub, topic) do
		Mqttex.SubscriberSet.match(sub, topic)
	end
	
end
