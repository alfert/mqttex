defmodule Mqttex.SupTopic do
    use Supervisor.Behaviour

    # name of the supervisor process
    @supervisor __MODULE__

    def start_link do
        :supervisor.start_link({:local, @supervisor}, __MODULE__, [])
    end

    def init([]) do
        children = [
            # a simple one for one supervisor has a basic child definition
            # with default arguments for all children, to which the 
            # current arguments are add while calling :supervisor.start_child
            worker(Mqttex.Topic, [], restart: :transient)
        ]

        # See http://elixir-lang.org/docs/stable/Supervisor.Behaviour.html
        # for other strategies and supported options
        supervise(children, strategy: :simple_one_for_one)
    end

    @doc """
    Creates a child specification for dynamically attaching a topic to 
    the supervisor hierarchy
    """
    def start_topic(topic) do
        # IO.puts "start topic for #{topic}"
        :supervisor.start_child @supervisor, [topic]
    end
  
end
