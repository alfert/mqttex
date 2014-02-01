defmodule MqttexClientTest do
	
	use ExUnit.Case

	test "Connect a client and send FaF" do
	  	{client, server} = connect("nobody", "passwd")
		body = "Message"
		Mqttex.Client.publish(client, "topic", body, :fire_and_forget)

		assert_receive (Mqttex.PublishMsg[message: ^body])
	end

	test "Connect a client and send ALO" do
	  	{client, server} = connect("nobody", "passwd")
		body = "ALO Message"
		Mqttex.Client.publish(client, "topic", body, :at_least_once)

		assert_receive (Mqttex.PublishMsg[message: ^body])
	end

	test "Connect a client and send AMO" do
	  	{client, server} = connect("nobody", "passwd")
		body = "ALO Message"
		Mqttex.Client.publish(client, "topic", body, :at_most_once)

		assert_receive (Mqttex.PublishMsg[message: ^body])
	end


	test "Receive a published Message (FaF)" do
		{client, server} = connect("nobody", "passwd")
		body = "FaF Message"
		Mqttex.Test.SessionAdapter.publish(server, "topic", body, :fire_and_forget)

		assert_receive (Mqttex.PublishMsg[message: ^body])
	end

	test "Receive a published Message (ALO)" do
		{client, server} = connect("nobody", "passwd")
		body = "ALO Message"
		Mqttex.Test.SessionAdapter.publish(server, "topic", body, :at_least_once)

		assert_receive (Mqttex.PublishMsg[message: ^body])
	end

	test "Receive a published Message (AMO)" do
		{client, server} = connect("nobody", "passwd")
		body = "ALO Message"
		Mqttex.Test.SessionAdapter.publish(server, "topic", body, :at_most_once)

		assert_receive (Mqttex.PublishMsg[message: ^body])
	end

	@doc """
	Configures the client and the test adapters. Returns client and server, respectively
	"""
	def connect(user, passwd) do
		{out_channel, in_channel, server} = setupQueue()
		{:ok, client} = Mqttex.Client.connect(user, passwd, self, out_channel)
		send(in_channel, {:register, client, Mqttex.Client})
		{client, server}		
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
		sessionReceiver = spawn_link(Mqttex.Test.SessionAdapter, :start, [chReceiver, final_receiver_pid])
		assert is_pid(sessionReceiver)
	
		# Register the Sessions as Targets for the Channels
		send(chSender, {:register, sessionReceiver})
		# send(chReceiver, {:register, sessionSender})

		IO.puts "Sender Channel is   #{inspect chSender}"
		IO.puts "Receiver Channel is #{inspect chReceiver}"
		IO.puts "Receiver Session is #{inspect sessionReceiver}"
  		IO.puts "Final Receiver is   #{inspect final_receiver_pid}"

		{chSender, chReceiver, sessionReceiver}
	end

end
