defmodule Mqttex.TopicManager do
	
	@moduledoc """
		
	"""

	use GenServer.Behaviour

	@my_name __MODULE__

	defrecord State, subscriptions: HashDict.new

	@doc """
	Publishes a messages, starting 
	"""
	@spec publish(Mqttex.PublishMsg.t, binary) :: :ok
	def publish(Mqttex.PublishMsg[] = msg, from) do
		# if the topic exists, publish it directly without 
		# interfering with the topic manager.
		try do
			Mqttex.Topic.publish(msg, from)
		catch
			# Topic does not exist, so start it. 
			:exit, {:no_proc, _} -> start_topic(msg, from)
			any -> throw any
		end
	end
	
	def start_topic(Mqttex.PublishMsg[] = msg, from) do
		:gen_server.call(@my_name, {:start_topic, msg, from})
	end
	
	def subscribe(Mqttex.SubscribeMsg[] = topics, from) do
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
		{:ok, State.new}
	end

	def handle_call({:start_topic, Mqttex.PublishMsg[topic: topic] = msg, from}, client, state) do
		# ignore any problems during start, in particular :already_started
		# because we call the topic server via its name. Any problems happening
		# from concurrent starts of the topics are resolved here: after start_topic
		# the topic must be there. Otherwise we have a severe problem to be solved
		# somewhere else.
		Mqttex.SubTopic.start_topic(topic) 
		Mqttex.Topic.publish(msg, from)
		# return value is missing!
		0 = 1 
	end
	def handle_call({:subscribe, Mqttex.SubscribeMsg[] = topics, from}, client, state) do
		# TODO
	end
	
	
	def subscribe_to({topic, qos}, from) do
		Mqttex.Topic.subscribe(topic, qos, from)
	end
	

end
