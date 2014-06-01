defmodule MqttexEncoderTest do
	@moduledoc """
	This test checks the encoding of regular Elixir structs to binary messages.
	"""
	# require Lager
	# import Bitwise
	use ExUnit.Case

	test "length encoding one byte" do
		assert Mqttex.Encoder.encode_length(127) == <<0x7f>>
		assert Mqttex.Encoder.encode_length(0) == <<0x00>>
	end

	test "length encoding two bytes" do
		assert Mqttex.Encoder.encode_length(128) == <<0x80,0x01>>
		assert Mqttex.Encoder.encode_length(16_383) == <<0xFF, 0x7F>>
	end

	test "length encoding three bytes" do
		assert Mqttex.Encoder.encode_length(16_384) == <<0x80, 0x80, 0x01>>
		assert Mqttex.Encoder.encode_length(2_097_151) == <<0xFF, 0xFF, 0x7F>>
	end

	test "length encoding four bytes" do
		assert Mqttex.Encoder.encode_length(2_097_152) == <<0x80, 0x80, 0x80, 0x01>>
		assert Mqttex.Encoder.encode_length(268_435_455) == <<0xFF, 0xFF, 0xFF, 0x7F>>
	end

	test "length encoding with more then four bytes fails" do
		catch_error Mqttex.Encoder.encode_length(268_435_456)
	end

	test "fixed header encoding" do
		header = %Mqttex.Msg.FixedHeader{}
		assert Mqttex.Encoder.encode_header(header) == <<0x00, 0x00>>
		assert Mqttex.Encoder.encode_header(Mqttex.Msg.fixed_header(:subscribe, 
			true, :exactly_once, true, 127)) == <<0x8d, 0x7f>>
	end

end