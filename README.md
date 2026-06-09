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
