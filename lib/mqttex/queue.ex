defmodule Mqttex.OutboundQueue do
	@moduledoc """
	This implements the outbound queue, publishing messages towards a single destination. 
	It uses the QoS Protocols to factor out the correct behaviour for `at least once` or for 
	`at most once` guarantees.
	"""

	use GenServer.Behaviour
	@behaviour Mqttex.SenderBehaviour

	defrecord QueueState, counter: 0, session: :none

	#####################################################################################
	### API
	#####################################################################################
	def publish(topic, message, qos) when 
		qos in [:fire_and_forget, :at_least_once, :at_most_once] do

		:genserver.cast({:publish, topic, message, qos})
	end
	
	#####################################################################################
	### callbacks
	#####################################################################################
	def handle_cast({:publish, topic, message, qos}, QueueState[] = state) do
		msg = make_publish(topic, message, qos, state.counter)
		pid = start_protocol(msg, qos)
		add_message_proc(pid)
		pid <- :go
	end
	
	def init([]) do
		{:ok, QueueState.new}
	end
	

	#####################################################################################
	### internal functions
	#####################################################################################
	def make_publish(topic, message, qos, msg_id) do
		header = Mqttex.FixedHeader.new [qos: qos, message_type: :publish]
		Mqttex.PublishMsg.new [header: header, topic: topic, message: message, msg_id: msg_id]
	end
	
	@doc """
	Starts and initializes a qos protocol process and returns its PID. The sending process becomes active
	after receiving the `:go` message. 
	"""
	def start_protocol(Mqttex.PublishMsg[] = msg, :fire_and_forget) do
		spawn(Mqttex.Qos0Sender.start(msg, __MODULE__, self))
	end
	def start_protocol(Mqttex.PublishMsg[] = msg, :at_least_once) do
		spawn(Mqttex.Qos1Sender.start(msg, __MODULE__, self))
	end
	def start_protocol(Mqttex.PublishMsg[] = msg, :at_most_once) do
		spawn(Mqttex.Qos2Sender.start(msg, __MODULE__, self))
	end

end
