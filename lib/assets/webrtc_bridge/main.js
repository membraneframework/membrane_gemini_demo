export function init(ctx, initial) {
  ctx.root.innerHTML = `
    <div style="background:#111;color:#eee;font-family:monospace;padding:12px;border-radius:6px;">
      <div style="display:flex;align-items:center;gap:12px;">
        <button id="connect" style="background:#2a6;border:0;color:white;padding:6px 12px;border-radius:4px;cursor:pointer;">
          Connect
        </button>
        <span id="status">Click Connect to grant mic access and start streaming.</span>
      </div>
      <audio id="player" autoplay style="display:none"></audio>
    </div>
  `;

  const statusEl = ctx.root.querySelector("#status");
  const audioEl = ctx.root.querySelector("#player");
  const button = ctx.root.querySelector("#connect");
  const setStatus = (msg) => { statusEl.textContent = msg; };

  // Messages received from the server before the PCs are built get buffered here.
  const queues = {
    source: (initial && initial.source_queue) ? initial.source_queue.slice() : [],
    sink: (initial && initial.sink_queue) ? initial.sink_queue.slice() : []
  };
  const pcs = {};

  const handleSourceMsg = async (msg) => {
    if (!pcs.source) { queues.source.push(msg); return; }
    if (msg.type === "sdp_answer") {
      await pcs.source.setRemoteDescription(msg.data);
    } else if (msg.type === "ice_candidate") {
      await pcs.source.addIceCandidate(msg.data);
    }
  };

  const handleSinkMsg = async (msg) => {
    if (!pcs.sink) { queues.sink.push(msg); return; }
    if (msg.type === "sdp_offer") {
      await pcs.sink.setRemoteDescription(msg.data);
      const answer = await pcs.sink.createAnswer();
      await pcs.sink.setLocalDescription(answer);
      ctx.pushEvent("signal_sink", { type: "sdp_answer", data: answer });
    } else if (msg.type === "ice_candidate") {
      await pcs.sink.addIceCandidate(msg.data);
    }
  };

  ctx.handleEvent("source_signal", handleSourceMsg);
  ctx.handleEvent("sink_signal", handleSinkMsg);

  // Bubble each peer connection's aggregate state (ICE + DTLS)
  // up to the Elixir bridge, which fans it out to subscribers.
  // "connected" is the moment the DTLS handshake has finished and media can flow.
  const reportState = (peer, pc) => {
    const push = () => ctx.pushEvent("peer_state", { peer, state: pc.connectionState });
    pc.addEventListener("connectionstatechange", push);
    push();
  };

  button.onclick = async () => {
    button.disabled = true;
    button.style.opacity = "0.5";
    try {
      setStatus("Requesting mic access…");

      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          channelCount: 1
        },
        video: false
      });

      // Sink PC: server -> browser
      pcs.sink = new RTCPeerConnection();
      pcs.sink.onicecandidate = (ev) => {
        if (ev.candidate) ctx.pushEvent("signal_sink", { type: "ice_candidate", data: ev.candidate });
      };
      audioEl.srcObject = new MediaStream();
      pcs.sink.ontrack = (ev) => {
        audioEl.srcObject.addTrack(ev.track);
        audioEl.play().catch(() => {});
      };
      reportState("sink", pcs.sink);

      // Source PC: browser -> server
      pcs.source = new RTCPeerConnection();
      pcs.source.onicecandidate = (ev) => {
        if (ev.candidate) ctx.pushEvent("signal_source", { type: "ice_candidate", data: ev.candidate });
      };
      for (const track of stream.getTracks()) pcs.source.addTrack(track, stream);
      reportState("source", pcs.source);

      // Drain anything that arrived before the PCs existed (notably the sink's SDP offer).
      for (const msg of queues.sink.splice(0)) await handleSinkMsg(msg);
      for (const msg of queues.source.splice(0)) await handleSourceMsg(msg);

      const offer = await pcs.source.createOffer();
      await pcs.source.setLocalDescription(offer);
      ctx.pushEvent("signal_source", { type: "sdp_offer", data: offer });

      setStatus("Connected. Speak into your mic — Gemini is listening.");
    } catch (err) {
      setStatus("Error: " + ((err && err.message) || String(err)));
      button.disabled = false;
      button.style.opacity = "1";
    }
  };
}
