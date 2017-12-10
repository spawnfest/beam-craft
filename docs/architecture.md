# Architecture

The general process layout for the minecraft server looks like:

```
                        +--+-------------+--+
          +------------^+  < game server >  |
          |             +--+-------------+--+
          |
          |
+---------+------------+    +--+------------+--+
|  <root application>  |---^+  < map server >  |
+---------+------------+    +--+------------+--+
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
The map server is responsible for managing all of the blocks and updating things like flowing water.
