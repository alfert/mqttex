defmodule Mqttex.SenderBehaviour do
	@moduledoc """
	This is a behaviour for sending messages called from the QoS Senders. 
	"""

	use Behaviour

	@type message_type :: Mqttex.Msg.Publish.t | Mqttex.Msg.Subscribe.t | Mqttex.Msg.Unsubscribe.t

	@doc """
	Sends a message and returns the current timeout for an answer in milliseconds. 
	The first parameter is either a `pid` or an named process references for a genserver.
	"""
	defcallback send_msg(term, message_type) :: integer

	@doc """
	Call after completing the protocol. Sends the value of protocol (usually an `:ok`) as third
	parameter. The protocol process is usually dead after this call.

	The first parameter is either a `pid` or an named process references for a genserver.
	"""
	defcallback send_complete(term, Mqttex.Msg.Simple.t) :: :ok

	@doc """
	Sends a release message and returns the current timeout for an answer in milliseconds. 
	The first parameter is either a `pid` or an named process references for a genserver.
	"""
	defcallback send_release(term, Mqttex.Msg.Simple.t) :: integer

	@doc """
	Sends a received message and returns the current timeout for an answer in milliseconds. 
	The first parameter is either a `pid` or an named process references for a genserver.
	"""
	defcallback send_release(term, Mqttex.Msg.Simple.t) :: integer

	@doc """
	Finishes the sender protocol. Usually this requires house-keeping activities for the 
	process managing the protocol processes.
	The first parameter is either a `pid` or an named process references for a genserver.
	The second paramter is the `msg_id` of the protocol
	"""
	defcallback finish_sender(term, integer) :: :ok
	
	@doc """
	Finishes the receiver protocol. Usually this requires house-keeping activities for the 
	process managing the protocol processes.
	The first parameter is either a `pid` or an named process references for a genserver.
	The second paramter is the `msg_id` of the protocol
	"""
	defcallback finish_receiver(term, integer) :: :ok


	# Emtpy default implementations
	defmacro __using__(_) do
    	quote location: :keep do
    		def send_msg(queue, msg) do
    			:error_logger.error_msg("Not implemted: #{__MODULE__}.send_msg(#{inspect queue}, #{inspect msg}")
    		end

    		def send_complete(queue, msg) do
    			:error_logger.error_msg("Not implemted: #{__MODULE__}.send_complete(#{inspect queue}, #{inspect msg}")
    		end

    		def send_release(queue, msg) do
    			:error_logger.error_msg("Not implemted: #{__MODULE__}.send_release(#{inspect queue}, #{inspect msg}")
    		end

    		def send_received(queue, msg) do
    			:error_logger.error_msg("Not implemted: #{__MODULE__}.send_received(#{inspect queue}, #{inspect msg}")
    		end

 	    	defoverridable [send_msg: 2, send_complete: 2, send_release: 2, send_received: 2]
    	end
    end
end

defmodule Mqttex.ReceiverBehaviour do
	@moduledoc """
	This is a behaviour for the receiver part of the qos transfers. It is not the client-side	
	interface.
	"""
	use Behaviour

	@doc """
	Message callback: Sends the message to given pid, when a message arrives and qos is completed
	"""
	defcallback on_message(pid, term) :: :ok

	defmacro __using__(_) do
		quote location: :keep do
			def on_message(_pid, _msg) do
				:error_logger.error_msg("Unimplemented  #{__MODULE__}.on_message")
			end

			defoverridable [on_message: 2]
		end
	end
end

defmodule Mqttex.QoS0Sender do
	@moduledoc """
	Implements a `fire and forget` sender protocol.
	"""

	@spec start(Mqttex.Msg.Publish.t, atom, pid) :: :ok
	def start(%Mqttex.Msg.Publish{} = msg, mod, sender) do
		receive do
			:go -> send_msg(msg, mod, sender)
		end
		mod.finish_sender(sender, self)
	end
	
	def send_msg(msg, mod, sender) do
		mod.send_msg(sender, msg)
		:ok
	end
end

defmodule Mqttex.QoS0Receiver do
	@moduledoc """
	Implements the receiver for the `fire and forget`protocol. Delegates the incoming
	message to the `on_message` function of the `receiver`'s module.
	"""
	@spec start(Mqttex.Msg.Publish.t, atom, pid) :: :ok
	def start(%Mqttex.Msg.Publish{} = msg, mod, receiver) do
		mod.on_message(receiver, msg)
		mod.finish_receiver(receiver, self)
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

	@spec start(Mqttex.Msg.Publish.t, atom, pid) :: :ok
	def start(%Mqttex.Msg.Subscribe{msg_id: id}   = msg, mod, sender), do: start(msg, id, mod, sender)
	def start(%Mqttex.Msg.Unsubscribe{msg_id: id} = msg, mod, sender), do: start(msg, id, mod, sender)
	def start(%Mqttex.Msg.Publish{msg_id: id}     = msg, mod, sender), do: start(msg, id, mod, sender)

	defp start(msg, id, mod, sender) do
		receive do
			:go -> send_msg(msg, id, mod, sender, :first)
		end
		mod.finish_sender(sender, self)
	end
	
	def send_msg(msg, id, mod, sender, duplicate) do
		m = Mqttex.Msg.Publish.duplicate(msg, duplicate == :second)
		timeout = mod.send_msg(sender, m)
		receive do
			%Mqttex.Msg.Simple{msg_type: :pub_ack, msg_id: ^id}   -> :ok
			%Mqttex.Msg.SubAck{msg_id: ^id}                       -> :ok
			%Mqttex.Msg.Simple{msg_type: :unsub_ack, msg_id: ^id} -> :ok
			# Mqttex.UnSubAckMsg[msg_id: ^id] -> :ok
			after  timeout                  -> send_msg(m, id, mod, sender, :second)
		end
	end

end

defmodule Mqttex.QoS1Receiver do
	@moduledoc """
	Implements the protocol of a receiver process that responds to a message by
	sending the acknowledgement. 

	This is the receiver part of `At least once` protocol of MQTT.
	"""

	@spec start(Mqttex.Msg.Publish.t, atom, pid) :: :ok
	def start(%Mqttex.Msg.Publish{} = msg, mod, receiver) do
		mod.on_message(receiver, msg)
		send_ack(msg.msg_id, mod, receiver)
		mod.finish_receiver(receiver, self)
	end

	def send_ack(msg_id, mod, receiver) do
		#ack = %Mqttex.Msg.Simple{msg_type: :pub_ack, msg_id: msg_id}
		ack = Mqttex.Msg.pub_ack(msg_id)
		mod.send_msg(receiver, ack)
		:ok		
	end

end

defmodule Mqttex.QoS2Sender do
	@moduledoc """
	Implements the protocol of a sender process that sends messages with QoS2, ie. 
	as `Exactly Once` quality of service. 
	"""

	@spec start(Mqttex.Msg.Publish.t, atom, pid) :: :ok
	def start(%Mqttex.Msg.Publish{} = msg, mod, sender) do
		receive do
			:go -> send_msg(msg, mod, sender, :first)
		end
		mod.finish_sender(sender, self)
	end
	
	@doc """
	Sends the message to the receiver. If no `PubRecMsg` arrives 
	within the timeout, we assume that the message is lost. The message
	is resend then (by tail recursion in to the very function). If the acknowledgement
	arrives within the timout, the process advances to releasing the message 
	(see `send_release`).
	"""
	def send_msg(%Mqttex.Msg.Publish{msg_id: msg_id} = msg, mod, sender, duplicate) do
		m = Mqttex.Msg.Publish.duplicate(msg, duplicate == :second)
		timeout = mod.send_msg(sender, m)
		receive do
			%Mqttex.Msg.Simple{msg_type: :pub_rec, msg_id: ^msg_id} -> send_release(msg_id, mod, sender, :first)
			any						 		  -> :error_logger.error_msg("Strange message: #{inspect any}")
			after  timeout                    -> send_msg(msg, mod, sender, :second)
		end
	end

	@doc """
	Sends a releasse message to the receiver. If no `PubCompMsg` arrives
	within the timeout, we assume that the message is lost. We resend the release
	message until a response arrives.
	"""
	def send_release(msg_id, mod, sender, duplicate) do
		m = Mqttex.Msg.pub_rel(msg_id, duplicate == :second)
		timeout = mod.send_release(sender, m)
		receive do
			%Mqttex.Msg.Simple{msg_type: :pub_comp, msg_id: ^msg_id} -> :ok
			after  timeout                                          -> send_release(msg_id, mod, sender, :second)
		end
	end

end

defmodule Mqttex.QoS2Receiver do
	@moduledoc """
	Implements the protocol for a QoS2 receiver, ie. the receiver part of the 
	`Exactly Once` quality of service. 
	"""

	@nr_of_timeout 5

	@spec start(Mqttex.Msg.Publish.t, atom, pid) :: :ok
	def start(%Mqttex.Msg.Publish{} = msg, mod, receiver) do
#		mod.on_message(receiver, msg)
		send_received(msg, msg.msg_id, mod, receiver, :first)
		mod.finish_receiver(receiver, self)
	end

	def send_received(msg, msg_id, mod, receiver, _duplicate) do
		received = Mqttex.Msg.pub_rec(msg_id)
		timeout = mod.send_received(receiver, received)
		receive do
			%Mqttex.Msg.PubRel{msg_id: ^msg_id} -> send_complete(msg, msg_id, mod, receiver, :first)
			%Mqttex.Msg.Publish{msg_id: ^msg_id} -> send_received(msg, msg_id, mod, receiver, :second)
			after timeout                        -> send_received(msg, msg_id, mod, receiver, :second)
		end
	end

	def send_complete(msg, msg_id, mod, receiver, _duplicate) do
		mod.on_message(receiver, msg)
		wait_for_completed_timeout(msg_id, mod, receiver, @nr_of_timeout)
	end

	@doc """
	The message transfer is completed in general, but the complete message may not arrive at
	the sender. As a result, he will send the release message again, waiting for the complete 
	message. Alas, this might never end. But to reduce this kind of failure, we wait a couple of 
	times and only after that time we declare the transer as finished. But who knows? Exactly Once 
	is broken by design.
	"""
	def wait_for_completed_timeout(msg_id, mod, receiver, 0), do: :ok
	def wait_for_completed_timeout(msg_id, mod, receiver, nr_of_timeout) do
		complete = Mqttex.Msg.pub_comp(msg_id)
		timeout = mod.send_complete(receiver, complete)
		receive do
			%Mqttex.Msg.PubRel{msg_id: ^msg_id} -> 
				wait_for_completed_timeout(msg_id, mod, receiver, nr_of_timeout - 1)
			after  timeout                    -> 
				wait_for_completed_timeout(msg_id, mod, receiver, nr_of_timeout - 1)
		end
	end

end