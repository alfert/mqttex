defmodule Mqttex.Topic do
	
	@moduledoc """
	Implements a single topic with a set of session subscriptions. 

	The message storage is defined as a parameter for each topic, also 
	the subscription storage. For the latter an efficient match support
	for wildcard subscriptions is important. 

	"""
	use GenServer.Behaviour

	### UML Specification
	# @startuml
	# class Topic <<Server>> {
	# 	start_link(topic)
	# 	publish(msg, client)
	# 	subscribe(topic, qos, client)
	# 	unsubscribe(topic, client)
	# }
	# @enduml

	defstruct topic: "", 
		subscriptions: HashDict.new()
	# 	 do
	# 	record_type topic: binary,
	# 		subscriptions:  Dict.t(binary, Mqttex.qos_type)
	# end

	def start_link(topic) when is_binary(topic) do
		:gen_server.start_link(topic_server(topic), __MODULE__,  topic, [])
	end
	
	def publish(%Mqttex.Msg.Publish{} = msg, client) do
		:gen_server.call(topic_server(msg), {:publish, msg, client})
	end
	
	@doc """
	Subscribes a `client` to the `topic` with requested `qos`. 
	Returns the granted qos.
	"""
	@spec subscribe(binary, Mqttex.qos_type, binary) :: Mqttex.qos_type
	def subscribe(topic, qos, client) do
		:gen_server.call(topic_server(topic), {:subscribe, client, qos})
	end

	@doc """
	Unsubscribes a `client` from the `topic`. It is guaranteed that 
	the client is no longer subscribed to the topic.
	"""
	@spec unsubscribe(binary, binary) :: :ok
	def unsubscribe(topic, client) do
		:gen_server.call(topic_server(topic), {:unsubscribe, client})
	end
		

	@doc "Returns the name of the `TopicServer` for the given topic."
	def topic_server(%Mqttex.Msg.Publish{topic: topic}) do
		topic_server(topic)
	end
	def topic_server(topic) when is_binary(topic) do
		{:global, {:topic, topic}}
	end

	

	####################################################################################
	### Callbacks
	####################################################################################

	def init(topic) do
		{:ok, %Topic{topic: topic} }
	end


	def handle_call({:publish, %Mqttex.Msg.Publish{message: content} = _msg, _client}, 
				    _from, %Topic{subscriptions: subs} = state) do
		Enum.each(subs, fn({session, qos}) -> send_msg(session, content, qos) end)
		{:reply, :ok, state}
	end
	def handle_call({:subscribe, client, qos}, _from, %Topic{subscriptions: subs} = state) do
		new_state = state.subscriptions(Dict.put(subs, client, qos))
		{:reply, qos, new_state}
	end
	def handle_call({:unsubscribe, client}, _from, %Topic{subscriptions: subs} = state) do
		new_subs = Dict.delete(client)
		new_state = state.subscriptions new_subs
		{:reply, :ok, new_state}
	end
	
	####################################################################################
	### Internal Implementation
	####################################################################################

	def send_msg(session, content, qos) do
		Mqttex.Server.send_msg(session, content, qos)
	end

end