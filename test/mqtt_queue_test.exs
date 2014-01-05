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
		Mqttex.OutboundQueue.publish(q, "AMO-Topic", msg, :at_least_once)

		assert_receive Mqttex.PublishMsg[message: ^msg] = any, 1_000
	end


	def setupQueue() do
		channel = spawn_link(Mqttex.TestChannel, :channel, [])
		assert is_pid(channel)
		channel <- {:register, self}

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