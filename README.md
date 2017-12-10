# beam-craft
by Lobsters

## Introduction

This is a simple Minecraft Classic server written in Elixir. It is compatable with the [ClassicSharp client](https://github.com/UnknownShadow200/ClassicalSharp).

The current test server is live at `minecraft.burnwillows.net`.

## Running The Server

```sh
	$ git clone https://github.com/spawnfest/beam-craft
	$ cd beam-craft
	$ mix deps.get
	$ mix run --no-halt
```

By default the server starts on port `5555` and listens on `0.0.0.0`.

## Running The Client

### Windows

Use the Windows release provided at the [ClassicSharp website](https://www.classicube.net/).

### Mac OS X / Linux

Use the Mac OS X / Linux release provided at the [ClassicSharp website](https://www.classicube.net/) under [Wine](https://www.winehq.org/).
To get all of the assets first run the launcher, then invoke the client directly like `wine ClassicalSharp.exe <username> <password> <ip> <port>`.

## Useful links

* [Elixir's woefully hidden docs on binary munging](https://github.com/elixir-lang/elixir/blob/master/lib/elixir/lib/kernel/special_forms.ex#L132)
* [Minecraft Classic protocol](https://minecraft.gamepedia.com/Classic_server_protocol#Packet_Protocol)
* [Minecraft Classic block types](https://minecraft.gamepedia.com/Java_Edition_data_values/Classic)
* [Lobsters](https://lobste.rs/)
