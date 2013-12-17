defmodule Mqttex.Topic do
	
	@moduledoc """
	
	"""

	defrecord State, topic: "", subscriptions: []

	def start_link(topic) when is_binary(topic) do
		:gen_server.start_link(topic_server(topic), __MODULE__,  topic, [])
	end
	
	def publish(Mqttex.PublishMsg[] = msg, client) do
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
	def topic_server(Mqttex.PublishMsg[topic: topic]) do
		topic_server(topic)
	end
	def topic_server(topic) when is_binary(topic) do
		{:global, {:topic, topic}}
	end

	def init(topic) do
		{:ok, State.new[topic: topic]}
	end
	

	####################################################################################
	### Callbacks
	####################################################################################

	def handle_call({:publish, Mqttex.PublishMsg[message: content] = _msg, client}, 
				    from, State[subscriptions: subs] = state) do
		Enum.each(subs, fn({session, qos}) -> send_msg(session, content, qos) end)
		{:reply, :ok, state}
	end
	def handle_call({:subscribe, client, qos}, _from, State[subscriptions: subs] = state) do
		new_state = state.subscriptions [{client, qos} | subs]
		{:reply, :fire_and_forget, new_state}
	end
	def handle_call({:unsubscribe, client}, _from, State[subscriptions: subs] = state) do
		new_subs = Enum.filter(subs, 
				fn {client, _} -> false 
					_          -> true end)
		new_state = state.subscriptions new_subs
		{:reply, :ok, new_state}
	end

	####################################################################################
	### Internal Implementation
	####################################################################################

	def send_msg(session, content, :fire_and_forget) do
		Mqttex.Server.send_msg(session, content, :fire_and_forget)
	end
	

	def handle_call({:unsubscribe, client, qos}, _from, State[subscriptions: subs] = state) do
		new_state = state.subscriptions [{client, qos} | subs]
		{:reply, :fire_and_forget, new_state}
	end

end