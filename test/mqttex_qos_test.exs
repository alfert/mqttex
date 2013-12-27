defmodule MqttexQosTest do
	
	use ExUnit.Case

	test "Fire And Forget" do
		msg = makePublishMsg("x", "nix")
		qos = spawn(Mqttex.Qos0Sender, :start, [msg, MqttextSimpleSenderAdapter, self])
		IO.puts "#{__MODULE__}: process is #{inspect self}"
		qos <- :go
		assert_receive(msg)
	end

	test "At Least Once - one time, good case" do
		IO.puts "Setting up channels"
		chIn  = spawn_link(__MODULE__, :channel, [])
		chOut = spawn_link(__MODULE__, :channel, [])

		IO.puts "Setting up Sender Adapter"
		adapter_pid    = spawn_link(MqttextSimpleSenderAdapter, :start, [chOut])
		chIn <- {:register, adapter_pid}

		IO.puts "Setting up Receiver Adapter"
		receiver_pid = spawn_link(MqttextSimpleSenderAdapter, :start_receiver, [chIn])
		chOut <- {:register, receiver_pid}

		# we self want to receive messages receiver by the adapter
		MqttextSimpleSenderAdapter.register_receiver(receiver_pid, self)

		# Here we go!
		IO.puts "Here we go!"
		msg = makePublishMsg("Topic ABO", "ABO Message", :at_most_once, 70)
		senderProtocol = MqttextSimpleSenderAdapter.publish(adapter_pid, msg)
		senderProtocol <- :go

		receive do
			Mqttex.PubAckMsg[] = ack -> assert ack.msg_id == msg.msg_id
			Mqttex.PublishMsg[] = received -> 
				IO.puts "#{IO.ANSI.cyan}Yeah, we received this message: #{inspect msg}#{IO.ANSI.white}"
				assert received.msg_id == msg.msg_id
			any -> flunk "Got invalid #{inspect any}"
			after 1000 -> flunk "Timout"
		end
	end

	test "At Most Once - one time, good case" do
		IO.puts "Setting up channels"
		chIn  = spawn_link(__MODULE__, :channel, [])
		chOut = spawn_link(__MODULE__, :channel, [])

		IO.puts "Setting up Sender Adapter"
		adapter_pid    = spawn_link(MqttextSimpleSenderAdapter, :start, [chOut])
		chIn <- {:register, adapter_pid}

		IO.puts "Setting up Receiver Adapter"
		receiver_pid = spawn_link(MqttextSimpleSenderAdapter, :start_receiver, [chIn])
		chOut <- {:register, receiver_pid}

		# we self want to receive messages receiver by the adapter
		MqttextSimpleSenderAdapter.register_receiver(receiver_pid, self)

		# Here we go!
		IO.puts "Here we go!"
		msg = makePublishMsg("Topic ABO", "ABO Message", :at_most_once, 70)
		senderProtocol = MqttextSimpleSenderAdapter.publish(adapter_pid, msg)
		senderProtocol <- :go

		receive do
			Mqttex.PubCompMsg[] = ack -> assert ack.msg_id == msg.msg_id
			Mqttex.PublishMsg[] = received -> 
				IO.puts "#{IO.ANSI.cyan}Yeah, we received this message: #{inspect msg}#{IO.ANSI.white}"
				assert received.msg_id == msg.msg_id
			any -> flunk "Got invalid #{inspect any}"
			after 1000 -> flunk "Timeout"
		end
	end

	@doc "Generates lazily a sequence of Publish Msgs"
	def generatePublishMsgs(qos, countStart) do
	end
	
	def makePublishMsg(topic, content, qos // :fire_and_forget, id // 0 ) do
		header= Mqttex.FixedHeader.new([qos: qos, message_type: :publish])
		Mqttex.PublishMsg.new([header: header, topic: topic, message: content, msg_id: id ])
	end
	
	@doc "A simple channel that forwards all messages it receives"
	def channel(state // []) do
		receive do
			{:register, receiver} -> 
				s = [receiver: receiver]
				channel(s)
			any -> 
				case state[:receiver] do
					nil -> # don't do any thing
						:error_logger.error_msg("Channel #{inspect self} got message #{inspect any}")
						channel(state)
					receiver -> 
						receiver <- any
						channel(state)
				end
		end
	end

end

defmodule MqttextSimpleSenderAdapter do
	use ExUnit.Case
	use Mqttex.SenderBehaviour
	@timeout 200

	def start(channel) do
		loop([channel: channel])
	end
	
	def loop(state) do
		new_state = receive do
			{:send, msg} -> 
				state[:channel] <- msg
				state
			{:register, qos} -> 
				Dict.put(state, :qos, qos)
			any -> 
				state[:qos] <- any
				state
		end
		loop(new_state)
	end

	def start_receiver(channel) do
		receiver_loop([channel: channel])
	end
	
	def receiver_loop(state) do
		new_state = receive do
			Mqttex.PublishMsg[] = msg -> 
				# we need a new qos protocol only, if does not yet exist. 
				# otherwise reuse it, we are in an ongoing protocol, PublishMsg
				# may be resent several times!
				case state[:qos] do
					nil -> qos = start_receiver_qos(msg)
						   Dict.put(state, :qos, qos)
					qos -> qos <- msg
						   state 
				end
			{:send, msg} ->
				state[:channel] <- msg
				state
			{:on_message, msg} ->
				state[:receiver] <- msg
				state
			{:receiver, receiver_pid} ->
				Dict.put(state, :receiver, receiver_pid)
			any ->
				state[:qos] <- any
				state
		end
		receiver_loop(new_state)
	end
	
	
	@doc "Publishes a message and returns the QoS protocol process"
	def publish(adapter_pid, Mqttex.PublishMsg[header: header] = msg) do
		qosProtocol = 
			case header.qos do
				:fire_and_forget -> spawn_link(Mqttex.QoS0Sender, :start, 
					[msg, MqttextSimpleSenderAdapter, adapter_pid])
				:at_least_once -> spawn_link(Mqttex.QoS1Sender, :start, 
					[msg, MqttextSimpleSenderAdapter, adapter_pid])
				:at_most_once -> spawn_link(Mqttex.QoS2Sender, :start, 
					[msg, MqttextSimpleSenderAdapter, adapter_pid])
			end
		adapter_pid <- {:register, qosProtocol}
		qosProtocol
	end
	
	def start_receiver_qos(Mqttex.PublishMsg[header: header] = msg) do
		qosProtocol = 
			case header.qos do
				:at_least_once -> spawn_link(Mqttex.QoS1Receiver, :start, 
					[msg, MqttextSimpleSenderAdapter, self])
				:at_most_once -> spawn_link(Mqttex.QoS2Receiver, :start, 
					[msg, MqttextSimpleSenderAdapter, self])
			end
		qosProtocol
	end

	def send_msg(adapter_pid, msg) do
		IO.puts "#{__MODULE__}: send_msg mit msg = #{inspect msg}"
		IO.puts "#{__MODULE__}: process is #{inspect self}"
		adapter_pid <- {:send, msg}
		@timeout
	end	

	def send_received(adapter_pid, msg) do
		IO.puts "#{__MODULE__}: send_received mit msg = #{inspect msg}"
		adapter_pid <- {:send, msg}
		@timeout
	end

	def send_release(adapter_pid, msg) do
		IO.puts "#{__MODULE__}: send_release mit msg = #{inspect msg}"
		adapter_pid <- {:send, msg}
		@timeout
	end

	def send_complete(adapter_pid, msg) do
		IO.puts "#{__MODULE__}: send_complete mit msg = #{inspect msg}"
		adapter_pid <- {:send, msg}
		@timeout
	end

	def on_message(adapter_pid, msg) do
		adapter_pid <- {:on_message, msg}
	end
	
	def register_receiver(adapter_pid, receiver_pid) do
		adapter_pid <- {:receiver, receiver_pid}
	end
end

defmodule MqttextSimpleReceiverQueue do
	use ExUnit.Case

	def start(receiver_mod, queue_pid, tester_mod // MqttextSimpleSenderAdapter) do
		receive do
			{:sender, sender_pid} -> wait_for_message(sender_pid, receiver_mod, queue_pid, tester_mod)
		end
	end

	def wait_for_message(sender_pid, receiver_mod, queue_pid, tester_mod) do
		receive do
			msg ->
				IO.puts("#{__MODULE__}.start Receiver with message #{inspect msg}")
				receiver_pid = spawn_link(receiver_mod, :start, [msg, tester_mod, sender_pid])
				wait_for_release(receiver_pid, sender_pid)
			after 1000 -> flunk("#{__MODULE__}.start: timeout, got no message")
		end		
	end

	def wait_for_release(receiver_pid, sender_pid) do
		IO.puts "#{__MODULE__}.wait for release"
		receive do
			Mqttex.PubRelMsg[] = msg -> 
				IO.puts "Got Release msg #{inspect msg}"
				receiver_pid <- msg
			any -> IO.puts("#{__MODULE__}.wait_for_release got bizarre msg #{inspect any} -> recurse")
				   wait_for_release(receiver_pid, sender_pid)
			after 1000 -> flunk("#{__MODULE__}.wait_for_release: timeout, got no message")
		end
	end
end