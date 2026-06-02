# Membrane Gemini TUI Demo

[![CircleCI](https://circleci.com/gh/membraneframework/membrane_gemini_demo.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_gemini_demo)

This repository contains an example chatbot app integrating the Google Live API using [`membrane_gemini_plugin`](https://github.com/membraneframework/membrane_gemini_plugin). It's a TUI app built using [Membrane](https://membrane.stream) for audio processing and [Termite](https://github.com/Gazler/termite) for the UI.

## Usage

To run the demo:
```
GEMINI_API_KEY="your API key" elixir native.exs
```
The script is self-contained — `Mix.install` fetches the deps, so there's no separate `mix deps.get` step. You can prompt Gemini via the text input field, or speak to it directly. Membrane will try using the default input device via [`membrane_portaudio_plugin`](https://github.com/membraneframework/membrane_portaudio_plugin). Press `m` to mute, `d` to show the event log, speech transcripts, etc. Send `/clear` via text prompt to reset the session context.

For the browser-based WebRTC variant (no native audio device needed), open `demo.livemd` in [Livebook](https://livebook.dev) and set `GEMINI_API_KEY` in its secrets.

NOTE: be sure to use headphones to avoid audio feedback, otherwise the LLM might start talking with itself.
