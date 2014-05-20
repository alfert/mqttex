defmodule MqttexQueueTest do
	@moduledoc """
	This test requires the Lossy Channel for checking that the protocols work for many 
	messages to send.
	"""
	require Lager
	use ExUnit.Case
	import Mqttex.Test.Tools

	test "Simple Send via Queue" do
		{q, qIn} = setupQueue()
		Lager.debug "q is #{inspect q}"
		Lager.debug "qIn is #{inspect qIn}"
		Mqttex.Test.SessionAdapter.send_msg(q, :hello)
		# this must fail, hello is not a proper message 
		assert_receive :hello, 200
		# receive do
		# 	msg -> Lager.debug "Got message #{inspect msg}"
		# 	after 200 -> Lager.debug "timeout :-("
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

	test "Publish EO via Queue" do
		{q, _qIn} = setupQueue()
		msg = "Initial Message EO"
		Mqttex.Test.SessionAdapter.publish(q, "EO-Topic", msg, :exactly_once)

		assert_receive Mqttex.PublishMsg[message: ^msg], 1_000
	end

	test "Publish ALO via Lossy Queue" do
		{q, _qIn} = setupQueue(70)
		msg = "Lossy Message ALO"
		Mqttex.Test.SessionAdapter.publish(q, "ALO-Topic", msg, :at_least_once)

		assert_receive Mqttex.PublishMsg[message: ^msg], 1_000
	end

	test "Publish EO via Lossy Queue" do
		{q, _qIn} = setupQueue(70)
		msg = "Lossy Message EO"
		Mqttex.Test.SessionAdapter.publish(q, "EO-Topic", msg, :exactly_once)

		assert_receive Mqttex.PublishMsg[message: ^msg], 1_100
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
		{q, _qIn} = setupQueue()
		messages = generateMessages(100)
		# Lager.debug "messages are: #{inspect messages}"

		bulk_send(messages, q, :at_least_once, "ALO-Topic")
		result = slurp()
		Lager.debug"Slurp result: #{inspect result}"
		Enum.each(messages, fn(m) -> assert result[m] > 0 end)
	end

	test "Many EO messages" do
		{q, _qIn} = setupQueue()
		message_count = 100
		messages = generateMessages(message_count)
		# Lager.debug "messages are: #{inspect messages}"

		bulk_send(messages, q, :exactly_once, "EO-Topic")
		result = slurp()
		Lager.debug "Slurp result: #{inspect result}"

		print_stats(message_count, Dict.size(result))

		assert message_count == Dict.size(result)
		Enum.each(messages, fn(m) -> assert result[m] == 1 end)
	end

	test "Many ALO messages via lossy queue" do
		{q, _qIn} = setupQueue(50)
		messages = generateMessages(100)
		# Lager.debug "messages are: #{inspect messages}"

		bulk_send(messages, q, :at_least_once, "ALO-Topic")
		result = slurp_all messages
		Lager.debug "Slurp result: #{inspect result}"
		Enum.each(messages, fn(m) -> assert result[m] > 0 end)
	end

	test "Many EO messages via lossy queue" do
		# {:ok, pid} = 
		# Mqttex.Test.MsgStat.start_link()

		{q, _qIn} = setupQueue(50)
		message_count = 100
		messages = generateMessages(message_count)
		# Lager.debug "messages are: #{inspect messages}"

		bulk_send(messages, q, :exactly_once, "EO-Topic") # , 3_000)

		result = slurp_all messages, Map.new, 1_000
		Lager.debug "Slurp result: #{inspect result}"
		
		print_stats(message_count, Dict.size(result))

		assert message_count == Dict.size(result)
		Enum.each(messages, fn(m) -> assert 1 == result[m] end)
	end


	setup do
		Mqttex.Test.MsgStat.start_link()
		:ok
	end
	
	teardown do
		Mqttex.Test.MsgStat.stop()
		:ok
	end
	

	def print_stats(message_count, result_count) do
		{msgs, losses} = Mqttex.Test.MsgStat.get_counts()
		IO.puts """
		Logical Messages sent:     #{message_count}
		Logical Messages received: #{result_count}
		Messages sent in Channel:  #{msgs}
		Messages lost in Channel:  #{losses}
		"""
	end
	

	@doc """
	Sends a bulk of messages into a queue, a topic and with a given QoS.
	"""
	def bulk_send(messages, q, qos, topic \\ "Any Topic", millis \\ 10) do
		Enum.each(messages, 
			fn(m) -> Mqttex.Test.SessionAdapter.publish(q, topic, m, qos) end)

		sleep(millis)
		send(self, :done)	
	end
			
	@doc """
	Slurps all messages once in order and after that slurps any remaining messages
	the process mailbox until `:done` is found
	"""
	def slurp_all([m | tail], found \\ Map.new, timeout \\ 5_000)
		when is_binary(m) do
		receive do
			Mqttex.PublishMsg[message: ^m] -> # when m == msg -> 
				Lager.debug("Gotcha: got #{m}")
				slurp_all(tail, Dict.update(found, m, 1, &(&1 + 1)), timeout)
			after timeout -> 
				Lager.debug("Nothing found for #{m} -> timeout")
				slurp_all(tail, found, timeout)
		end
	end
	def slurp_all([], found, _timeout), do: slurp(found)
	def slurp_all(%Stream.Lazy{} = stream, found, timeout) do
		slurp_all(Enum.to_list(stream), found, timeout)
	end

	@doc """
	Slurps all messages and counts how often each message occurs. 
	"""
	def slurp(msgs \\ Map.new) do
		receive do
			Mqttex.PublishMsg[message: m] ->	
				slurp(Dict.update(msgs, m, 1, &(&1 + 1)))
			:done -> msgs
			any -> Lager.info("slurp got any = #{inspect any}")
				slurp(msgs)
			after 1_000 -> msgs
		end
	end
	
	def generateMessages(count) do
		range = 1..count 
		Stream.map(range, &("Message #{&1}"))
	end
		

	@doc """
	Does the setup for all channels, receivers. Parameters:

	* `loss`: the amount of message loss in percent. Defaults to `0` 
	* `final_receiver_pid`: the final receiver of the message, defaults to `self`
	"""
	def setupQueue(loss \\ 0, final_receiver_pid \\ self) do
		if (loss == 0) do
			Lager.debug "Setting up channels"
		else
			Lager.debug "Setting up lossy channel (loss = #{loss})"
		end
		losslist = %{loss: loss, stats: true}
		# Create Outbound and Inbound Communication Channels
		chSender = spawn_link(Mqttex.Test.Channel, :channel, [losslist])
		assert is_pid(chSender)
		chReceiver = spawn_link(Mqttex.Test.Channel, :channel, [losslist])
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
