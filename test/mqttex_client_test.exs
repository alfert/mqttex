defmodule MqttexClientTest do
	require Lager
	use ExUnit.Case

	test "Connect a client and send FaF" do
	  	{client, _server} = connect("nobody", "passwd")
		body = "Message"
		Mqttex.Client.publish(client, "topic", body, :fire_and_forget)

		assert_receive (%Mqttex.Msg.Publish{message: ^body})
	end

	test "Connect a client and send ALO" do
	  	{client, _server} = connect("nobody", "passwd")
		body = "ALO Message"
		Mqttex.Client.publish(client, "topic", body, :at_least_once)

		assert_receive (%Mqttex.Msg.Publish{message: ^body})
	end

	test "Connect a client and send EO" do
	  	{client, _server} = connect("nobody", "passwd")
		body = "ALO Message"
		Mqttex.Client.publish(client, "topic", body, :exactly_once)

		assert_receive (%Mqttex.Msg.Publish{message: ^body})
	end


	test "Receive a published Message (FaF)" do
		{_client, server} = connect("nobody", "passwd")
		body = "FaF Message"
		Mqttex.Test.SessionAdapter.publish(server, "topic", body, :fire_and_forget)

		assert_receive (%Mqttex.Msg.Publish{message: ^body})
	end

	test "Receive a published Message (ALO)" do
		{_client, server} = connect("nobody", "passwd")
		body = "ALO Message"
		Mqttex.Test.SessionAdapter.publish(server, "topic", body, :at_least_once)

		assert_receive (%Mqttex.Msg.Publish{message: ^body})
	end

	test "Receive a published Message (EO)" do
		{_client, server} = connect("nobody", "passwd")
		body = "ALO Message"
		Mqttex.Test.SessionAdapter.publish(server, "topic", body, :exactly_once)

		assert_receive (%Mqttex.Msg.Publish{message: ^body})
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
	def setupQueue(loss \\ 0, final_receiver_pid \\ self) do
		if (loss == 0) do
			Lager.debug "Setting up channels"
		else
			Lager.debug "Setting up lossy channel (loss = #{loss})"
		end
		losslist = %{loss: loss}
		# Create Outbound and Inbound Communication Channels
		chSender = spawn_link(Mqttex.Test.Channel, :channel, [losslist])
		assert is_pid(chSender)
		chReceiver = spawn_link(Mqttex.Test.Channel, :channel, [losslist])
		assert is_pid(chReceiver)

		# Sessions encapsule the Communication Channels
		sessionReceiver = spawn_link(Mqttex.Test.SessionAdapter, :start, [chReceiver, final_receiver_pid])
		assert is_pid(sessionReceiver)
	
		# Register the Sessions as Targets for the Channels
		send(chSender, {:register, sessionReceiver})
		# send(chReceiver, {:register, sessionSender})

		Lager.debug "Sender Channel is   #{inspect chSender}"
		Lager.debug "Receiver Channel is #{inspect chReceiver}"
		Lager.debug "Receiver Session is #{inspect sessionReceiver}"
  		Lager.debug "Final Receiver is   #{inspect final_receiver_pid}"

		{chSender, chReceiver, sessionReceiver}
	end

end
