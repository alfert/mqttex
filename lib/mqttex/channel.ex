defmodule Mqttex.TestChannel do
	@moduledoc """
	This module provide a simple channel, that is lossy and reorders the messages. 
	It is used for testing only. 
	"""

	@doc "A simple channel that forwards all messages it receives"
	def channel(state // [loss: 0]) do
		receive do
			{:register, receiver} -> 
				s = Dict.put(state, :receiver, receiver)
				channel(s)
			any -> 
				case state[:receiver] do
					nil -> # don't do any thing
						:error_logger.error_msg("Channel #{inspect self} got message #{inspect any}")
						channel(state)
					receiver -> 
						# handle message-loss: If random number is lower than 
						# the message-loss, we swallow the message and do not send it to 
						# to the receiver.
						lossRnd = :random.uniform(100)
						#IO.puts ("lossRnd = #{lossRnd}")
						# IO.puts ("state = #{inspect state}")
						if (state[:loss] < lossRnd) do
							receiver <- any
						else
							:error_logger.error_msg "Swallow the message #{inspect any}"
						end
						channel(state)
				end
		end
	end

end