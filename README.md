# MQTTex

This a MQTT server and client written in Elixir. 

[![Build Status](https://travis-ci.org/alfert/mqttex.png)](https://travis-ci.org/alfert/mqttex)

## Design

For the design, here is a simple example in Elixir: 

``` elixir
def f(p) do
	IO.puts "param: #{p}"
end

``` 


### Connections

One process per logical client connection (i.e. operating on Elixir data structures). On 
the physical connection we have an additional process, which does the network handling
and the encoding/decoding of MQTT messages. The connection state holds the list of subscription
strings, i.e. with wildcards. It also holds the client process to which published messages are send. 

### Subscriptions of topics

Subscriptions of topics are managed by a registration service and Topic Server for each topic. 
The topic server holds a list of subscribed clients and the witheld messages. The registration service
provides functions to find all known topics for a subscription string and for subscribing and 
unsubscribing, i.e. interacting with the topic servers. The subscriptions can be stored in an 
DETS/ETS to survive potential crashes of the topic servers. 

The task of a topic server is receive messages to be published and send them to the subscribed
connections. It also handles the QoQ workflow with each client connection. 

### Supervising

The supervised processes for connections and for topics are dynamically by nature. For both 
a separate supervisor exists. 

## The MQTT state machine

### Server Side 

The several states are shown here the statechart: 

![FSM of the Server Side](../mqtt-server-fsm.dot.png)

### Client Side

## Handling Topics and QoS (server side)

The outbound traffic for a destination must be handled via a queue. If the
destination is not connected, but we have a durable session (and thus durable
subscriptions), all messages send to the destination are held in the server
and delivered after a reconnect. 

In the destination queue the messages are represented as quadruples of
`{topic, msg_id, qos, content}. 

![Server Side Structure](../server-structure.dot.png)


### Fire and Forget

At fire and forget, the server session handles the incoming message as cast
and gives it  to the topic to handle it further on. The topic gives the
message to  the subscribed sessions,  which in return sends them directly to
the client-process (usually handling the tcp connection).

### At Least Once

The server session has to acknowlegde the incoming publish message. This is
done directly in the server session. The message (and its duplicates) are send
to the topic, which distributes it to the subscribed sessions.  If the
subscribed sessions also requires `at least once`, the transfer to the
destination can only finish after a successful acknowledgement from the
client. Without an acknowldgement, the message is published again (as a
duplicate) to the destination.

The destination session in the broker has to manage the state of transfer,
i.e. it can only drop the message if the destination client has sucessfully
send an PubAck message. Essentially this is a queue of messages, consisting
of triples `{topic, msg_id, message}`. The timeout after which a retry is done
can be varying (similar to exponential timeout). It might be easier to
understand the queue triple as a separate process for which timer events are
handled.

### At most once



## ToDos

### Specific todos
* verify connections
* document client side approach

### Generic todos
* add more unit tests
* add statemachine tests with Proper

