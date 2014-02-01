defmodule MqttexQueueTest do
	@moduledoc """
	This test requires the Lossy Channel for checking that the protocols work for many 
	messages to send.
	"""

	use ExUnit.Case

	test "Simple Send via Queue" do
		{q, qIn} = setupQueue()
		ref = Process.monitor(qIn)
		IO.puts "q is #{inspect q}"
		IO.puts "qIn is #{inspect qIn}"
		Mqttex.Test.SessionAdapter.send_msg(q, :hello)
		# this must fail, hello is not a proper message 
		assert_receive :hello, 200
		# receive do
		# 	msg -> IO.puts "Got message #{inspect msg}"
		# 	after 200 -> IO.puts "timeout :-("
		# end
		# assert_receive {:DONE, ^ref, _, _, _},  200
	end

	test "Publish FaF via Queue" do
		{q, _qIn} = setupQueue()
		msg = "Initial Message FaF"
		Mqttex.Test.SessionAdapter.publish(q, "FAF-Topic", msg, :fire_and_forget)

		assert_receive Mqttex.PublishMsg[message: ^msg], 1_000
	end

	test "Publish ALO via Queue" do
		{q, _qIn} = setupQueue()
		msg = "Initial Message ALO"
		Mqttex.Test.SessionAdapter.publish(q, "ALO-Topic", msg, :at_least_once)

		assert_receive Mqttex.PublishMsg[message: ^msg], 1_000
	end

	test "Publish AMO via Queue" do
		{q, qIn} = setupQueue()
		msg = "Initial Message AMO"
		Mqttex.Test.SessionAdapter.publish(q, "AMO-Topic", msg, :at_most_once)

		assert_receive Mqttex.PublishMsg[message: ^msg] = any, 1_000
	end

	test "Publish ALO via Lossy Queue" do
		{q, qIn} = setupQueue(70)
		msg = "Lossy Message ALO"
		Mqttex.Test.SessionAdapter.publish(q, "ALO-Topic", msg, :at_least_once)

		assert_receive Mqttex.PublishMsg[message: ^msg] = any, 1_000
	end

	test "Publish AMO via Lossy Queue" do
		{q, qIn} = setupQueue(70)
		msg = "Lossy Message AMO"
		Mqttex.Test.SessionAdapter.publish(q, "AMO-Topic", msg, :at_most_once)

		assert_receive Mqttex.PublishMsg[message: ^msg] = any, 1_100
	end

	test "Publish two ALOs" do
		{q, _qIn} = setupQueue()
		msg1 = "Initial Message ALO"
		Mqttex.Test.SessionAdapter.publish(q, "ALO-Topic", msg1, :at_least_once)
		assert_receive Mqttex.PublishMsg[message: ^msg1], 1_000

		msg2 = "2nd Message ALO"
		Mqttex.Test.SessionAdapter.publish(q, "ALO-Topic", msg2, :at_least_once)
		assert_receive Mqttex.PublishMsg[message: ^msg2], 1_000
	end


	test "Many ALO messages" do
		{q, qIn} = setupQueue()
		messages = generateMessages(100)
		# IO.puts "messages are: #{inspect messages}"

		bulk_send(messages, q, :at_least_once, "ALO-Topic")
		result = slurp()
		IO.puts "Slurp result: #{inspect result}"
		Enum.each(messages, fn(m) -> assert result[m] > 0 end)
	end

	test "Many AMO messages" do
		{q, qIn} = setupQueue()
		messages = generateMessages(100)
		# IO.puts "messages are: #{inspect messages}"

		bulk_send(messages, q, :at_most_once, "AMO-Topic")
		result = slurp()
		IO.puts "Slurp result: #{inspect result}"
		Enum.each(messages, fn(m) -> assert result[m] == 1 end)
	end

	test "Many ALO messages via lossy queue" do
		{q, qIn} = setupQueue(50)
		messages = generateMessages(100)
		# IO.puts "messages are: #{inspect messages}"

		bulk_send(messages, q, :at_least_once, "ALO-Topic")
		result = slurp()
		IO.puts "Slurp result: #{inspect result}"
		Enum.each(messages, fn(m) -> assert result[m] > 0 end)
	end

	test "Many AMO messages via lossy queue" do
		{q, qIn} = setupQueue(50)
		messages = generateMessages(100)
		# IO.puts "messages are: #{inspect messages}"

		bulk_send(messages, q, :at_most_once, "AMO-Topic", 3_000)
		result = slurp()
		IO.puts "Slurp return #{inspect Dict.size(result)}"
		IO.puts "Slurp result: #{inspect result}"
		Enum.each(messages, fn(m) -> assert result[m] == 1 end)
	end


	@doc """
	Sends a bulk of messages into a queue, a topic and with a given QoS.
	"""
	def bulk_send(messages, q, qos, topic // "Any Topic", millis // 10) do
		Enum.each(messages, 
			fn(m) -> Mqttex.Test.SessionAdapter.publish(q, topic, m, qos) end)

		sleep(millis)
		send(self, :done)			
	end
			

	@doc """
	Sluprs all messages and counts how often each message occurs. 
	"""
	def slurp(msgs // ListDict.new) do
		receive do
			Mqttex.PublishMsg[message: m] ->	
				slurp(Dict.update(msgs, m, 1, &(&1 + 1)))
			:done -> msgs
			any -> IO.puts ("slurp got any = #{inspect any}")
				slurp(msgs)
			after 1_000 -> msgs
		end
	end
	

	def generateMessages(count) do
		range = 1..count 
		result = Stream.map(range, &("Message #{&1}"))
	end
	
	def sleep(millis // 1_000) do
		receive do
			after millis -> nil
		end		
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
		# Create Outbound and Inbound Communication Channels
		chSender = spawn_link(Mqttex.TestChannel, :channel, [losslist])
		assert is_pid(chSender)
		chReceiver = spawn_link(Mqttex.TestChannel, :channel, [losslist])
		assert is_pid(chReceiver)

		# Sessions encapsule the Communication Channels
		sessionSender = spawn_link(Mqttex.Test.SessionAdapter, :start, [chSender, final_receiver_pid])
		assert is_pid(sessionSender)
		sessionReceiver = spawn_link(Mqttex.Test.SessionAdapter, :start, [chReceiver, final_receiver_pid])
		assert is_pid(sessionReceiver)
	
		# Register the Sessions as Targets for the Channels
		send(chSender, {:register, sessionReceiver})
		send(chReceiver, {:register, sessionSender})
  
		{sessionSender, sessionReceiver}
	end

end
