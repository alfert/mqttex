defmodule Mqttex.Test.Tools do
	require Lager

	@moduledoc """
	Some tool and utility functions for testing purposes.
	"""

	def wait_for_shutdown(ref, millis \\ 1_000) do
		receive do
			{:DOWN, ^ref, _type, _object, _info} ->
				Lager.info "Got DOWN message"
				:ok
			after millis -> 				
				Lager.error "Process #{inspect ref} does NOT exit properly!"
				:timeout
		end		
	end
	
	def sleep(millis \\ 1_000) do
		receive do
			after millis -> :ok
		end
	end
	

end