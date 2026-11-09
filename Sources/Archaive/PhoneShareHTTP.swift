import Foundation

// Keep routing independent of capture so session isolation can be tested without permissions.
enum PhoneShareHTTP {
    enum Route { case page, frame, missing }

    static func route(_ request: Data, token: String) -> Route {
        guard let text = String(data: request, encoding: .utf8),
              let line = text.components(separatedBy: "\r\n").first else { return .missing }
        let parts = line.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "GET", parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0" else { return .missing }
        if parts[1] == "/\(token)/" { return .page }
        if parts[1] == "/\(token)/frame" { return .frame }
        return .missing
    }

    static let page = #"""
    <!doctype html>
    <html lang="en">
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-title" content="Archaive">
    <meta name="theme-color" content="#101713">
    <meta name="referrer" content="no-referrer">
    <title>Archaive · Mac screen</title>
    <style>
    :root { color-scheme:dark; font:16px -apple-system,BlinkMacSystemFont,system-ui,sans-serif; background:#101713; color:#f4f7f5; }
    * { box-sizing:border-box; }
    body { margin:0; min-height:100dvh; padding: max(16px,env(safe-area-inset-top)) max(16px,env(safe-area-inset-right)) max(16px,env(safe-area-inset-bottom)) max(16px,env(safe-area-inset-left)); display:flex; flex-direction:column; gap:16px; }
    header { display:flex; align-items:center; justify-content:space-between; gap:12px; }
    h1 { font-size:20px; margin:0; font-weight:600; }
    button { font:inherit; color:#fff; background:#285c40; border:1px solid #78ac8a; border-radius:8px; min-height:44px; padding:10px 16px; cursor:pointer; }
    button:hover { background:#356f50; }
    button:focus-visible { outline:3px solid #b4edc5; outline-offset:3px; }
    ::selection { background:#b4edc5; color:#101713; }
    main { flex:1; display:grid; place-items:center; min-height:220px; overflow:auto; }
    img { display:block; width:100%; height:auto; background:#101713; }
    img[hidden] { display:none; }
    body.zoom img { width:auto; max-width:none; }
    footer { color:#b9cabe; font-size:14px; line-height:1.5; }
    p { margin:0; }
    #status { color:#f4f7f5; margin-bottom:4px; }
    </style>
    <header><h1>Archaive</h1><button id="fit" aria-pressed="false">Actual size</button></header>
    <main><img id="screen" hidden alt="Live view of your Mac screen"></main>
    <footer><p id="status" role="status" aria-live="polite">Connecting to your Mac…</p>
    <p>Your Mac’s dimming does not affect this view. Adjust brightness on your phone. Stop sharing from the Mac menu.</p></footer>
    <script>
    const screen = document.getElementById('screen');
    const status = document.getElementById('status');
    let previousURL;
    document.getElementById('fit').onclick = function () {
      const zoom = document.body.classList.toggle('zoom');
      this.textContent = zoom ? 'Fit screen' : 'Actual size';
      this.setAttribute('aria-pressed', String(zoom));
    };
    async function refresh() {
      if (!document.hidden) {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 4000);
        try {
          const response = await fetch('frame', {cache:'no-store', signal:controller.signal});
          if (!response.ok) throw new Error('No frame');
          const url = URL.createObjectURL(await response.blob());
          screen.src = url;
          if (previousURL) URL.revokeObjectURL(previousURL);
          previousURL = url;
          screen.hidden = false;
          status.textContent = 'Live · Mac screen';
        } catch (_) {
          screen.hidden = true;
          status.textContent = 'Screen unavailable. Check sharing on your Mac and connect both devices to the same network. Retrying…';
        } finally { clearTimeout(timeout); }
      }
      setTimeout(refresh, 125);
    }
    refresh();
    </script>
    </html>
    """#
}
