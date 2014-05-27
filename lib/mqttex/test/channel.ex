defmodule Mqttex.Test.Channel do
	require Lager
	@moduledoc """
	This module provide a simple channel, that is lossy and reorders the messages. 
	It is used for testing onlys. 
	"""

	@doc "A simple channel that forwards all messages it receives"
	def channel(state \\ %{loss: 0, stats: false}) do
		receive do
			{:register, receiver} -> 
				s = Dict.put(state, :receiver, receiver)
				channel(s)
			{:register, receiver, mod} -> 
				s = Dict.put(state, :receiver, receiver)
				s1 = Dict.put(s, :mod, mod)
				channel(s1)
			any -> 
				case state[:receiver] do
					nil -> # don't do any thing
						Lager.error("Channel #{inspect self} ignores message #{inspect any}")
						channel(state)
					receiver -> 
						# handle message-loss: If random number is lower than 
						# the message-loss, we swallow the message and do not send it to 
						# to the receiver.
						lossRnd = :random.uniform(100)
						# Lager.debug ("lossRnd = #{lossRnd}")
						# Lager.debug ("state = #{inspect state}")
						if (state[:loss] < lossRnd) do
							send_msg(receiver, any, state)
							if state[:stats], do: Mqttex.Test.MsgStat.new_msg 
						else
							Lager.debug "Swallow the message #{inspect any}"
							if state[:stats], do: Mqttex.Test.MsgStat.new_loss
						end
						channel(state)
				end
		end
	end

	@doc "Sends a message, either directly or via the receiver api"
	def send_msg(receiver, msg, state) do
		case state[:mod] do
			nil -> send(receiver, msg)
			mod -> mod.receive(receiver, msg)
		end
	end

end

defmodule Mqttex.Test.SessionAdapter do
	@moduledoc """
	Adapter for Sessions
	"""
	require Lager
	use Mqttex.SenderBehaviour
	use Mqttex.ReceiverBehaviour

	@timeout 200

	defrecord State, 
		senders: Mqttex.ProtocolManager.new(), 
		receivers: Mqttex.ProtocolManager.new(),
		final: nil

	def start(chOut, final \\ self) when is_pid(chOut) and is_pid(final) do
		state = State.new(final: final)
		loop(chOut, state)
	end

	def publish(session, topic, body, qos) do
		msg = Mqttex.Msg.publish(topic, body, qos)
		publish(session, msg)
	end
	
	
	def publish(session, %Mqttex.Msg.Publish{} = msg) do
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
				Lager.info("State of #{inspect self}: #{inspect state}")
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
				# Lager.info("on_message: #{inspect msg}\nSending to #{inspect state.final}")
				send(state.final, msg)
				loop(channel, state)
			{:publish, pub} ->
				new_sender = Mqttex.ProtocolManager.sender(state.senders, pub, __MODULE__, self)
				loop(channel, state.update(senders: new_sender))
			%Mqttex.Msg.Publish{} = pub ->
				new_rec = Mqttex.ProtocolManager.receiver(state.receivers, pub, __MODULE__, self)
				loop(channel, state.update(receivers: new_rec))
			msg -> 
				case Mqttex.ProtocolManager.dispatch_receiver(state.receivers, msg) do
					:error ->
						case Mqttex.ProtocolManager.dispatch_sender(state.senders, msg) do
							:error ->
								Lager.debug("#{__MODULE__}.loop #{inspect self}: got unknown message #{inspect msg}")
								send(state.final, msg)
								# raise binary_to_atom("#{inspect msg}")
							_ -> :ok
						end
					_ -> :ok
				end
				loop(channel, state)
		end
	end
	
end