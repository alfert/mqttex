defmodule Mqttex.Topic do
	
	@moduledoc """
	
	"""

	defrecord State, topic: "", subscriptions: []

	def start_link(topic) do
		:gen_server.start_link(topic)
	end
	
	def publish(msg, from) do
		:gen_server.call(topic_server(msg), {:publish, msg, from})
	end
	
	def topic_server(Mqttex.PublishMsg[topic: topic]) do
		topic_server(topic)
	end
	def topic_server(topic) when is_binary(topic) do
		{:global, {:topic, topic}}
	end

	def init(topic) do
		{:ok, State.new[topic: topic]}
	end
	

end