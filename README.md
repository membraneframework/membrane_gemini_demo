# Membrane Gemini TUI Demo

<img width="960" height="573" alt="output" src="https://github.com/user-attachments/assets/a264640b-577e-4e9f-a7cb-d1b2c5801e20" />

This repository contains a simple chatbot app utilising the Google Live API via [`membrane_gemini_plugin`](https://github.com/membraneframework/membrane_gemini_plugin). It's a TUI app built using [Membrane](https://membrane.stream) for audio processing and [Termite](https://github.com/Gazler/termite) for the UI.

## Usage

We recommend running the demo via [livebook](demo.livemd).

To run the native demo:
```
GEMINI_API_KEY="your API key" elixir native.exs
```
You can prompt Gemini via the text input field, or speak to it directly. Membrane will try using the default input device via [`membrane_portaudio_plugin`](https://github.com/membraneframework/membrane_portaudio_plugin). NOTE: since PortAudio doesn't provide echo cancellation, be sure to use headphones to avoid audio feedback and Gemini replying to itself.

## Structure

The demo works around two processes - the Membrane pipeline and the `Membrane.LLM.Demo.App` GenServer. The latter receives events from the former and modifies the TUI appropriately.

Additional Membrane elements are provided to facilitate communication between the pipeline and TUI.

1. `Membrane.LLM.Demo.TuiSink` - Forwards audio samples, thinking prompts, transcripts, etc. from `Membrane.Gemini.Bin` to the `App` GenServer.  Useful reference for how events that `Membrane.Gemini.Bin` sends downstream can be handled for integration with modules outside the pipeline.
2. `Membrane.LLM.Demo.MuteFilter` - Toggles between forwarding audio buffers arriving on its input pad and silence. The toggle is controlled by parent notifications. In the examples, these are triggered by the TUI when it receives a `/mute` command in the text input prompt.
3. `Membrane.LLM.Demo.TextSource` - Similar to `Membrane.LLM.Demo.MuteFilter`, receives text via parent notification and forwards it on its output pad. In the example, it is linked to the `:text_input` pad of `Membrane.Gemini.Bin`, and the notifications are triggered by text input prompts from the TUI.
