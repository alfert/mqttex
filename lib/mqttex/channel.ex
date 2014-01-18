defmodule Mqttex.TestChannel do
	@moduledoc """
	This module provide a simple channel, that is lossy and reorders the messages. 
	It is used for testing only. 
	"""

	@doc "A simple channel that forwards all messages it receives"
	def channel(state // [loss: 0]) do
		receive do
			{:register, receiver} -> 
				s = Dict.put(state, :receiver, receiver)
				channel(s)
			any -> 
				case state[:receiver] do
					nil -> # don't do any thing
						:error_logger.error_msg("Channel #{inspect self} got message #{inspect any}")
						channel(state)
					receiver -> 
						# handle message-loss: If random number is lower than 
						# the message-loss, we swallow the message and do not send it to 
						# to the receiver.
						lossRnd = :random.uniform(100)
						#IO.puts ("lossRnd = #{lossRnd}")
						# IO.puts ("state = #{inspect state}")
						if (state[:loss] < lossRnd) do
							send(receiver, any)
						else
							:error_logger.error_msg "Swallow the message #{inspect any}"
						end
						channel(state)
				end
		end
	end

end

defmodule Mqttex.Test.SessionAdapter do
	@moduledoc """
	Adapter for Sessions
	"""

	use Mqttex.SenderBehaviour
	use Mqttex.ReceiverBehaviour

	@timeout 200

	defrecord State, 
		senders: Mqttex.ProtocolManager.new(), 
		receivers: Mqttex.ProtocolManager.new(),
		final: nil

	def start(chOut, final // self) when is_pid(chOut) and is_pid(final) do
		state = State.new(final: final)
		loop(chOut, state)
	end

	def publish(session, topic, body, qos) do
		header = Mqttex.FixedHeader.new([qos: qos])
		msg = Mqttex.PublishMsg.new([header: header, topic: topic, message: body])
		publish(session, msg)
	end
	
	
	def publish(session, Mqttex.PublishMsg[] = msg) do
		send(session, {:publish, msg})
	end

	def on_message(session, msg) do
		send(session, {:on, msg})		
	end

	def print_state(session) do
		send(session, :print_state)
	end
							

	@doc """
	Sends the message to the channel
	"""
	def send_msg(session, msg) do
		send(session, {:send, msg})
		@timeout
	end
	def send_received(session, msg) do
		send(session, {:send, msg})
		@timeout
	end
	def send_release(session, msg) do
		send(session, {:send, msg})
		# send(session, {:drop_sender, msg})
		@timeout
	end
	def send_complete(session, msg) do
		send(session, {:send, msg})
		#send(session, {:drop_receiver, msg})
		@timeout
	end
	def finish_sender(session, msg_id) do
		send(session, {:drop_sender, msg_id})
	end
	def finish_receiver(session, msg_id) do
		send(session, {:drop_receiver, msg_id})
	end
	
			

	def loop(channel, state) do
		receive do
			:print_state -> 
				IO.puts("State of #{inspect self}: #{inspect state}")
				loop(channel, state)
			{:send, msg} -> 
				send(channel, msg)
				loop(channel, state)
			{:drop_sender, msg_id} ->
				new_sender = Mqttex.ProtocolManager.delete(state.senders, msg_id)
				loop(channel, state.update(senders: new_sender))
			{:drop_receiver, msg_id} ->
				new_receiver = Mqttex.ProtocolManager.delete(state.receivers, msg_id)
				loop(channel, state.update(receivers: new_receiver))
			{:on, msg} -> 
				# :error_logger.info_msg("on_message: #{inspect msg}\nSending to #{inspect state.final}")
				send(state.final, msg)
				loop(channel, state)
			{:publish, pub} ->
				new_sender = Mqttex.ProtocolManager.sender(state.senders, pub, __MODULE__, self)
				loop(channel, state.update(senders: new_sender))
			Mqttex.PublishMsg[] = pub ->
				new_rec = Mqttex.ProtocolManager.receiver(state.receivers, pub, __MODULE__, self)
				loop(channel, state.update(receivers: new_rec))
			msg -> 
				case Mqttex.ProtocolManager.dispatch_receiver(state.receivers, msg) do
					:error ->
						case Mqttex.ProtocolManager.dispatch_sender(state.senders, msg) do
							:error ->
								# TODO:
								# We come here. This means, the message cannot not be identified
								# to a running qos process. This should not happen. Why is this 
								# so? 
								# ==> Looks like a nasty interference of timeouts and async sends. 
								# After a send release we drop the sender, but it should got the
								# completed message and die afterwards. Including the removal 
								# from qos map. Hmm. How to do this properly?
								IO.puts ("MqttexSessionAdapter.loop #{inspect self}: got unknown message #{inspect msg}")
								send(state.final, msg)
								raise binary_to_atom("#{inspect msg}")
							_ -> :ok
						end
					_ -> :ok
				end
				loop(channel, state)
		end
	end
	
end