# Architecture

The general process layout for the minecraft server looks like:

```
                        +--+-------------+--+
          +------------^+  < game server >  |
          |             +--+-------------+--+
          |
          |
+---------+------------+
|  <root application>  |
+---------+------------+
          |
          |             +--+--------------+--+
          +------------^+  < ranch server >  |
                        ++-+--------------+--+
                         |
                         |
                         |   +-+----------------+-+
                         +---+ < client handler > |
                         |   +--------------------+
                         |   +--------------------+
                         +---+ < client handler > |
                             +-+----------------+-+

```

Client handlers are Ranch processes that handle translating to and from our game server message format.

The game server is responsible for managing world state and routing messages and whatnot.
