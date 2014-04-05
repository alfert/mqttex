defmodule MqttexQosTest do
	require Lager
	use ExUnit.Case

	test "Fire And Forget" do
		body = "FaF Message"
		msg = makePublishMsg("Topic FaF", body)
		setupChannels(msg)
		assert_receive Mqttex.PublishMsg[message: ^body]
	end

	
	test "At Least Once - one time, good case" do
		msg = makePublishMsg("Topic ALO", "ALO Message", :at_least_once, 35)
		setupChannels(msg)

		receive do
			Mqttex.PubAckMsg[] = ack -> assert ack.msg_id == msg.msg_id
			Mqttex.PublishMsg[] = received -> 
				Lager.debug "Yeah, we received this message: #{inspect received}"
				assert received.msg_id == msg.msg_id
			any -> flunk "Got invalid #{inspect any}"
			after 1000 -> flunk "Timout"
		end
	end

	test "At Most Once - one time, good case" do
		msg = makePublishMsg("Topic EO", "EO Message", :exactly_once, 70)
		setupChannels(msg)

		receive do
			Mqttex.PubCompMsg[] = ack -> assert ack.msg_id == msg.msg_id
			Mqttex.PublishMsg[] = received -> 
				Lager.debug "Yeah, we received this message: #{inspect received}"
				assert received.msg_id == msg.msg_id
			any -> flunk "Got invalid #{inspect any}"
			after 1000 -> flunk "Timeout"
		end
	end

	test "At Least Once - one time, lossy channel" do
		msg_id = 36
		msg = makePublishMsg("Topic ALO", "Lossy ALO Message", :at_least_once, msg_id)
		setupChannels(msg, 70)

		assert_receive Mqttex.PublishMsg[msg_id: ^msg_id] = _received, 1000
		# Lager.debug "Yeah, we received this message: #{inspect received}"
	end

	test "At Most Once - one time, lossy channel" do
		msg_id = 72
		msg = makePublishMsg("Topic EO", "Lossy EO Message", :exactly_once, msg_id)
		setupChannels(msg, 70)

		assert_receive Mqttex.PublishMsg[msg_id: ^msg_id] = _received, 2000
		# Lager.debug "Yeah, we received this message: #{inspect received}"
	end

	def makePublishMsg(topic, content, qos \\ :fire_and_forget, id \\ 0 ) do
		header= Mqttex.FixedHeader.new([qos: qos, message_type: :publish])
		Mqttex.PublishMsg.new([header: header, topic: topic, message: content, msg_id: id ])
	end
	
	@doc """
	Does the setup for all channels, receivers. Parameters:

	* `msg`: the message to send
	* `loss`: the amount of message loss in percent. Defaults to `0` 
	* `final_receiver_pid`: the final receiver of the message, defaults to `self`

	"""
	def setupChannels(msg, loss \\ 0, final_receiver_pid \\ self) do
		if (loss == 0) do
			Lager.debug "Setting up channels"
		else
			Lager.debug "Setting up lossy channel (loss = #{loss})"
		end
		losslist = ListDict.new [loss: loss]
		chIn  = spawn_link(Mqttex.Test.Channel, :channel, [losslist])
		chOut = spawn_link(Mqttex.Test.Channel, :channel, [losslist])

		#Lager.debug "Setting up Sender Adapter"
		adapter_pid    = spawn_link(MqttextSimpleSenderAdapter, :start, [chOut])
		send(chIn, {:register, adapter_pid})

		#Lager.debug "Setting up Receiver Adapter"
		receiver_pid = spawn_link(MqttextSimpleSenderAdapter, :start_receiver, [chIn])
		send(chOut, {:register, receiver_pid})

		# we self want to receive messages receiver by the adapter
		MqttextSimpleSenderAdapter.register_receiver(receiver_pid, final_receiver_pid)

		# Here we go!
		#Lager.debug "Here we go!"
		senderProtocol = MqttextSimpleSenderAdapter.publish(adapter_pid, msg)
		send(senderProtocol, :go)
	end
end


defmodule MqttextSimpleSenderAdapter do
	require Lager
	use ExUnit.Case
	use Mqttex.SenderBehaviour
	@timeout 200

	def start(channel) do
		loop([channel: channel])
	end
	
	def loop(state) do
		new_state = receive do
			{:send, msg} -> 
				send(state[:channel], msg)
				state
			{:register, qos} -> 
				Dict.put(state, :qos, qos)
			any -> 
				send(state[:qos], any)
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
					qos -> send(qos, msg)
						   state 
				end
			{:send, msg} ->
				send(state[:channel], msg)
				state
			{:on_message, msg} ->
				send(state[:receiver], msg)
				state
			{:receiver, receiver_pid} ->
				Dict.put(state, :receiver, receiver_pid)
			any ->
				send(state[:qos], any)
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
				:exactly_once -> spawn_link(Mqttex.QoS2Sender, :start, 
					[msg, MqttextSimpleSenderAdapter, adapter_pid])
			end
		send(adapter_pid, {:register, qosProtocol})
		qosProtocol
	end
	
	def start_receiver_qos(Mqttex.PublishMsg[header: header] = msg) do
		qosProtocol = 
			case header.qos do
				:fire_and_forget -> spawn_link(Mqttex.QoS0Receiver, :start, 
					[msg, MqttextSimpleSenderAdapter, self])
				:at_least_once -> spawn_link(Mqttex.QoS1Receiver, :start, 
					[msg, MqttextSimpleSenderAdapter, self])
				:exactly_once -> spawn_link(Mqttex.QoS2Receiver, :start, 
					[msg, MqttextSimpleSenderAdapter, self])
			end
		qosProtocol
	end

	def send_msg(adapter_pid, msg) do
		#Lager.debug "#{__MODULE__}: send_msg mit msg = #{inspect msg}"
		#Lager.debug "#{__MODULE__}: process is #{inspect self}"
		send(adapter_pid, {:send, msg})
		@timeout
	end	

	def send_received(adapter_pid, msg) do
		#Lager.info "#{__MODULE__}: send_received mit msg = #{inspect msg}"
		send(adapter_pid, {:send, msg})
		@timeout
	end

	def send_release(adapter_pid, msg) do
		#Lager.debug "#{__MODULE__}: send_release mit msg = #{inspect msg}"
		send(adapter_pid, {:send, msg})
		@timeout
	end

	def send_complete(adapter_pid, msg) do
		#Lager.debug "#{__MODULE__}: send_complete mit msg = #{inspect msg}"
		send(adapter_pid, {:send, msg})
		@timeout
	end

	def on_message(adapter_pid, msg) do
		send(adapter_pid, {:on_message, msg})
	end
	
	def register_receiver(adapter_pid, receiver_pid) do
		send(adapter_pid, {:receiver, receiver_pid})
	end

	# this is a no-op here
	def finish_sender(_adapter_pid, _msg_id) do
		:ok
	end
	# this is a no-op here
	def finish_receiver(_adapter_pid, _msg_id) do
		:ok
	end
	
end

defmodule MqttextSimpleReceiverQueue do
	require Lager
	use ExUnit.Case

	def start(receiver_mod, queue_pid, tester_mod \\ MqttextSimpleSenderAdapter) do
		receive do
			{:sender, sender_pid} -> wait_for_message(sender_pid, receiver_mod, queue_pid, tester_mod)
		end
	end

	def wait_for_message(sender_pid, receiver_mod, _queue_pid, tester_mod) do
		receive do
			msg ->
				Lager.debug("#{__MODULE__}.start Receiver with message #{inspect msg}")
				receiver_pid = spawn_link(receiver_mod, :start, [msg, tester_mod, sender_pid])
				wait_for_release(receiver_pid, sender_pid)
			after 1000 -> flunk("#{__MODULE__}.start: timeout, got no message")
		end		
	end

	def wait_for_release(receiver_pid, sender_pid) do
		Lager.debug "#{__MODULE__}.wait for release"
		receive do
			Mqttex.PubRelMsg[] = msg -> 
				Lager.debug "Got Release msg #{inspect msg}"
				send(receiver_pid, msg)
			any -> Lager.warning("#{__MODULE__}.wait_for_release got bizarre msg #{inspect any} -> recurse")
				   wait_for_release(receiver_pid, sender_pid)
			after 1000 -> flunk("#{__MODULE__}.wait_for_release: timeout, got no message")
		end
	end
end