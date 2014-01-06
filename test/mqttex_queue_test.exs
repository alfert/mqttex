defmodule MqttexQueueTest do
	@moduledoc """
	This test requires the Lossy Channel for checking that the protocols work for many 
	messages to send.
	"""

	use ExUnit.Case

	test "Simple Send via Queue" do
		q = setupQueue()
		Mqttex.OutboundQueue.send_msg(q, :hallo)
		assert_receive :hallo, 200
	end

	test "Publish FaF via Queue" do
		q = setupQueue()
		msg = "Initial Message FaF"
		Mqttex.OutboundQueue.publish(q, "FAF-Topic", msg, :fire_and_forget)

		assert_receive Mqttex.PublishMsg[message: ^msg] = any, 1_000
	end

	test "Publish ALO via Queue" do
		q = setupQueue()
		msg = "Initial Message ALO"
		Mqttex.OutboundQueue.publish(q, "ALO-Topic", msg, :at_least_once)

		assert_receive Mqttex.PublishMsg[message: ^msg] = any, 1_000
	end

	test "Publish AMO via Queue" do
		q = setupQueue()
		msg = "Initial Message AMO"
		Mqttex.OutboundQueue.publish(q, "AMO-Topic", msg, :at_most_once)

		assert_receive Mqttex.PublishMsg[message: ^msg] = any, 1_000
	end

	test "Publish ALO via Lossy Queue" do
		q = setupQueue(70)
		msg = "Lossy Message ALO"
		Mqttex.OutboundQueue.publish(q, "ALO-Topic", msg, :at_least_once)

		assert_receive Mqttex.PublishMsg[message: ^msg] = any, 1_000
	end


	@doc """
	Does the setup for all channels, receivers. Parameters:

	* `loss`: the amount of message loss in percent. Defaults to `0` 
	* `final_receiver_pid`: the final receiver of the message, defaults to `self`
	"""
	def setupQueue(loss // 0, final_receiver_pid // self) do
		if (loss == 0) do
			IO.puts "Setting up channels"
		else
			IO.puts "Setting up lossy channel (loss = #{loss})"
		end
		losslist = ListDict.new [loss: loss]
		channel = spawn_link(Mqttex.TestChannel, :channel, [losslist])
		assert is_pid(channel)
		channel <- {:register, final_receiver_pid}

		session = spawn_link(MqttexSessionAdapter, :loop, [channel])
		assert is_pid(session)

		{:ok, q} = Mqttex.OutboundQueue.start_link(session, MqttexSessionAdapter)
		assert is_pid(q)
		q
	end

end

defmodule MqttexSessionAdapter do
	@moduledoc """
	Adapter for Sessions
	"""

	@doc """
	Sends the message to the channel
	"""
	def send_msg(session, msg) do
		session <- {:send, msg}
	end
	

	def loop(channel) do
		receive do
			{:send, msg} -> 
				channel <- msg
				loop(channel)
			any -> 
				IO.puts ("MqttexSessionAdapter.loop: got unknown message #{inspect any}")
				loop(channel)
		end
	end
	

end