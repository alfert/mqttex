defmodule Mqttex.SenderBehaviour do
	@moduledoc """
	This is a behaviour for sending messages called from the QoS Senders. 
	"""

	use Behaviour

	@doc """
	Sends a message and returns the current timeout for an answer in milliseconds. 
	The first parameter is either a `pid` or an named process references for a genserver.
	"""
	defcallback send_msg(term, Mqttex.PublishMsg.t) :: integer

	@doc """
	Call after completing the protocol. Sends the value of protocol (usually an `:ok`),
	the protocol process is usually dead after this call.

	The first parameter is either a `pid` or an named process references for a genserver.
	"""
	defcallback completed(term, pid, term) :: :ok

	@doc """
	Sends a release message and returns the current timeout for an answer in milliseconds. 
	The first parameter is either a `pid` or an named process references for a genserver.
	"""
	defcallback send_release(term, Mqttex.PubRelMsg.t) :: integer

end

defmodule Mqttex.Qos0Sender do
	@moduledoc """
	Implements a `fire and forget` sender protocol. There is no receiver, because nothing
	has to be exchanged between sender and receiver beyond the first message.
	"""

	@spec start(Mqttex.PublishMsg.t, atom, pid) :: :ok
	def start(Mqttex.PublishMsg[] = msg, mod, sender) do
		ok = receive do
			:go -> send_msg(msg, mod, sender)
		end
		mod.completed(sender, self, ok)
	end
	
	def send_msg(msg, mod, sender) do
		mod.send_msg(sender, msg)
		:ok
	end
end

defmodule Mqttex.QoS1Sender do
	@moduledoc """
	Implements the behaviour of a sender process that expects acknowledgements from the 
	receiver process. This implementation handles all resends of duplicate messages due 
	to timeouts between sender and receiver. The "real" sender is not hard-coded but 
	is a parameter of the process.

	The behaviour or the protocol for MQTT QoS 1, ie. At Least Once, is realized as a
	state machine with interleaving functions. This works because we have tail-call-optimization 
	in Erlang and Elixir.
	"""

	@spec start(Mqttex.PublishMsg.t, atom, pid) :: :ok
	def start(Mqttex.PublishMsg[] = msg, mod, sender) do
		receive do
			:go -> send_msg(msg, mod, sender, :first)
		end
	end
	
	def send_msg(Mqttex.PublishMsg[msg_id: id] = msg, mod, sender, duplicate) do
		m = msg.header.duplicate(duplicate == :second)
		timeout = mod.send_msg(sender, msg)
		receive do
			Mqttex.PubAckMsg[msg_id: id] -> :ok
			after timeout                -> send_msg(msg, mod, sender, :second)
		end
	end

end

defmodule Mqttex.QoS1Receiver do
	@moduledoc """
	Implements the protocol of a receiver process that responds to a message by
	sending the acknowledgement. 

	This is the receiver part of `At least once` protocol of MQTT.
	"""

	@spec start(Mqttex.PublishMsg.t, atom, pid) :: :ok
	def start(Mqttex.PublishMsg[] = msg, mod, receiver) do
		send_ack(msg.msg_id, mod, receiver)
	end

	def send_ack(msg_id, mod, receiver) do
		ack = Mqttex.PubAckMsg[msg_id: msg_id]
		mod.send_msg(receiver, ack)
		:ok		
	end

end

defmodule Mqttex.QoS2Sender do
	@moduledoc """
	Implements the protocol of a sender process that sends messages with QoS2, ie. 
	as `At Most Once` quality of service. 
	"""

	@spec start(Mqttex.PublishMsg.t, atom, pid) :: :ok
	def start(Mqttex.PublishMsg[] = msg, mod, sender) do
		receive do
			:go -> send_msg(msg, mod, sender, :first)
		end
	end
	
	@doc """
	Sends the message to the receiver. If no `PubRecMsg` arrives 
	within the timeout, we assume that the message is lost. The message
	is resend then (by tail recursion in to the very function). If the acknowledgement
	arrives within the timout, the process advances to releasing the message 
	(see `send_release`).
	"""
	def send_msg(Mqttex.PublishMsg[msg_id: msg_id] = msg, mod, sender, duplicate) do
		m = msg.header.duplicate(duplicate == :second)
		timeout = mod.send_msg(sender, m)
		receive do
			Mqttex.PubRecMsg[msg_id: msg_id] -> send_release(msg_id, mod, sender, :first)
			after timeout                    -> send_msg(msg, mod, sender, :second)
		end
	end

	@doc """
	Sends a releasse message to the receiver. If no `PubCompMsg` arrives
	within the timeout, we assume that the message is lost. We resend the release
	message until a response arrives.
	"""
	def send_release(msg_id, mod, sender, duplicate) do
		header = Mqttex.FixedHeader[duplicate: duplicate == :second]
		m = Mqttex.PubRelMsg[header: header, msg_id: msg_id]
		timeout = mod.send_release(sender, m)
		receive do
			Mqttex.PubCompMsg[msg_id: msg_id] -> :ok
			after timeout                     -> send_release(msg_id, mod, sender, :second)
		end
	end

end

defmodule Mqttex.QoS2Receiver do
	@moduledoc """
	Implements the protocol for a QoS2 receiver, ie. the receiver part of the 
	`At Most Once` quality of service. 
	"""

	@spec start(Mqttex.PublishMsg.t, atom, pid) :: :ok
	def start(Mqttex.PublishMsg[] = msg, mod, receiver) do
		receive do
			Mqttex.PublishMsg[] = msg -> send_received(msg.msg_id, mod, receiver, :first)
		end
	end

	def send_received(msg_id, mod, receiver, duplicate) do
		received = Mqttex.PubRecMsg[msg_id: msg_id]
		timeout = mod.send_received(receiver, received)
		receive do
			Mqttex.PublishMsg[] = msg -> send_received(msg_id, mod, receiver, :second)
			Mqttex.PubRelMsg[msg_id: msg_id] -> send_complete(msg_id, mod, receiver, :first)
			after timeout -> send_received(msg_id, mod, receiver, :second)
		end
	end

	def send_complete(msg_id, mod, receiver, duplicate) do
		complete = Mqttex.PubCompMsg[msg_id: msg_id]
		mod.send_complete(receiver, complete)
		:ok
	end

end