defmodule MqttexElixirTest do
	require Lager
	use ExUnit.Case

	@moduledoc """
	This modules figures out how to handle Maps and Structs instead of Records. 
	"""

	defstruct msg_id: true

	test "instantiate PubAck and directly match it" do
		k = 25
		l = k + 1
		m = make_PubAck k
		
		assert k == m.msg_id
		assert (%Mqttex.Msg.Simple{msg_type: :pub_ack, msg_id: ^k} = m)
		refute (%Mqttex.Msg.Simple{msg_type: :pub_ack, msg_id: ^l} = m)
		assert (%Mqttex.Msg.Simple{msg_type: :pub_ack} = m) 
		refute (%Mqttex.Msg.Simple{msg_type: :pub_ack} === m) 
	end

	test "get values from structs" do
		k = 28
		m = make_PubAck k

		assert k == get_msg_id1 m
		assert k == get_msg_id2 m
	end

	test "dispatch on structs" do
		k = 27
		m = make_PubAck k

		assert k == get_msg_id3 m
	end

	def make_PubAck(msg_id \\ 0) do
		%Mqttex.Msg.Simple{msg_type: :pub_ack, msg_id: msg_id}
	end
	
	def get_msg_id1(%Mqttex.Msg.Simple{msg_type: :pub_ack, } = m) do
		m.msg_id
	end
	def get_msg_id2(%Mqttex.Msg.Simple{msg_type: :pub_ack, msg_id: id}) do
		id
	end

	def get_msg_id3(%MqttexElixirTest{} = m), do: m.msg_id
	def get_msg_id3(%Mqttex.Msg.Simple{msg_type: :pub_ack, } = m), do: m.msg_id
	def get_msg_id3(any), do: false
	


end