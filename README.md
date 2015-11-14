Chatty
======

A basic IRC client that is most useful for writing a bot.


## Installation

Add Chatty as a dependency to your Mix project:

```elixir
def application do
  [applications: [:chatty]]
end

defp deps do
  [{:chatty, github: "alco/chatty"}]
end
```


## Usage

You need to set the following environment parameters for the `:chatty` app:

  * `:nickname` – the nick to use when connecting and identifying with NickServ
  * `:channels` – a list of channel names (in strings) to join upon connect
  * `:password` (optional) – when set, Chatty will identify with NickServ using
    this password
  * `:host` - A string with the address of the IRC network you want to connect to. 
  * `:port` - The IRC port Chatty will use. Check the server's configuration for its SSL port (or ask its admins).
  * `:ssl` (optional) - set to `true` or `false`. Chatty will rely on what you said to enable SSL mechanisms during network operations.

Chatty's behaviour is customized by means of adding hooks that get invoked on
each incoming message. A ping hook is included as an example. Set it up as
follows:

```iex
iex> Chatty.add_hook :ping, &Chatty.Hooks.PingHook.run/2, in: :text, direct: true
:ok
```

Now, whenever Chatty sees the message `<nickname>: ping`, it will send a reply
from the set of predefined ones back to the sender:

```
02:05:35      @true_droid | beamie_test: ping
02:05:35      beamie_test | true_droid: pong
```


## License

This software is licensed under [the MIT license](LICENSE).
